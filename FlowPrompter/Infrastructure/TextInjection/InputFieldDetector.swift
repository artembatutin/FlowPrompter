//
//  InputFieldDetector.swift
//  FlowPrompter
//
//  Created by Artem Batutin on 2026-01-28.
//

import Foundation
import AppKit
import Combine

/// Represents a detected input field in an application
struct DetectedInputField {
    let element: AXUIElement
    let role: String
    let placeholder: String?
    let value: String?
    let title: String?
    let windowTitle: String?
    let bundleId: String
    let appName: String
    
    /// Confidence score for this being the target input (0.0 - 1.0)
    var confidence: Double = 0.0
}

/// Patterns to match when searching for input fields
struct InputFieldPattern: Codable, Identifiable, Equatable {
    var id: String { pattern }
    let pattern: String
    let isRegex: Bool
    let matchType: MatchType
    var enabled: Bool
    
    enum MatchType: String, Codable {
        case placeholder   // Match against placeholder text
        case title         // Match against field title/label
        case value         // Match against current value
        case any           // Match against any attribute
    }
    
    init(pattern: String, isRegex: Bool = false, matchType: MatchType = .placeholder, enabled: Bool = true) {
        self.pattern = pattern
        self.isRegex = isRegex
        self.matchType = matchType
        self.enabled = enabled
    }
}

/// Service that detects and focuses input fields in applications
@MainActor
final class InputFieldDetector: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var lastDetectedField: DetectedInputField?
    @Published private(set) var isScanning: Bool = false
    @Published var patterns: [InputFieldPattern] = []
    @Published var autoFocusEnabled: Bool = true
    
    // MARK: - Configuration
    
    /// Default patterns to search for
    private static let defaultPatterns: [InputFieldPattern] = [
        // AI Chat interfaces
        InputFieldPattern(pattern: "ask anything", matchType: .placeholder),
        InputFieldPattern(pattern: "Ask Cascade", matchType: .placeholder),
        InputFieldPattern(pattern: "Ask Claude", matchType: .placeholder),
        InputFieldPattern(pattern: "Ask AI", matchType: .placeholder),
        InputFieldPattern(pattern: "Type a message", matchType: .placeholder),
        InputFieldPattern(pattern: "Send a message", matchType: .placeholder),
        InputFieldPattern(pattern: "Message", matchType: .placeholder),
        InputFieldPattern(pattern: "Chat", matchType: .placeholder),
        
        // Search fields
        InputFieldPattern(pattern: "Search", matchType: .placeholder),
        
        // Generic input patterns
        InputFieldPattern(pattern: "Type here", matchType: .placeholder),
        InputFieldPattern(pattern: "Enter text", matchType: .placeholder),
    ]
    
    /// Roles that indicate text input fields
    private let inputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField"
    ]
    
    /// Maximum depth to traverse in the UI hierarchy
    private let maxTraversalDepth: Int = 15
    
    // MARK: - Storage
    
    private let patternsStorageKey = "InputFieldPatterns"
    private let autoFocusStorageKey = "InputFieldAutoFocus"
    
    // MARK: - Initialization
    
    init() {
        loadSettings()
        if patterns.isEmpty {
            patterns = Self.defaultPatterns
        }
    }
    
    // MARK: - Public Methods
    
    /// Scans the frontmost application for matching input fields
    /// - Returns: The best matching input field, if found
    func scanForInputField() async -> DetectedInputField? {
        guard !isScanning else { return lastDetectedField }
        
        isScanning = true
        defer { isScanning = false }
        
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier,
              let appName = frontmostApp.localizedName else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }
        
        var allFields: [DetectedInputField] = []
        
        // Scan each window
        for window in windows {
            let windowTitle = getStringAttribute(window, attribute: kAXTitleAttribute)
            let fields = scanElement(window, depth: 0, windowTitle: windowTitle, bundleId: bundleId, appName: appName)
            allFields.append(contentsOf: fields)
        }
        
        // Score and sort fields
        let scoredFields = allFields.map { field -> DetectedInputField in
            var scored = field
            scored.confidence = calculateConfidence(for: field)
            return scored
        }.sorted { $0.confidence > $1.confidence }
        
        lastDetectedField = scoredFields.first
        return lastDetectedField
    }
    
    /// Focuses the specified input field
    /// - Parameter field: The field to focus
    /// - Returns: True if focus was successful
    @discardableResult
    func focusField(_ field: DetectedInputField) -> Bool {
        // Method 1: Try to set focus directly via accessibility
        let focusResult = AXUIElementSetAttributeValue(field.element, kAXFocusedAttribute as CFString, true as CFTypeRef)
        
        if focusResult == .success {
            return true
        }
        
        // Method 2: Try pressing the element (simulates a click via accessibility)
        let pressResult = AXUIElementPerformAction(field.element, kAXPressAction as CFString)
        
        if pressResult == .success {
            return true
        }
        
        // Method 3: Simulate a mouse click at the element's position
        // This works better for Electron-based apps (VS Code, Windsurf, etc.)
        if let position = getElementPosition(field.element),
           let size = getElementSize(field.element) {
            let clickPoint = CGPoint(
                x: position.x + size.width / 2,
                y: position.y + size.height / 2
            )
            return simulateClick(at: clickPoint)
        }
        
        return false
    }
    
    /// Gets the position of an accessibility element
    private func getElementPosition(_ element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success else {
            return nil
        }
        
        var point = CGPoint.zero
        if AXValueGetValue(positionRef as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }
    
    /// Gets the size of an accessibility element
    private func getElementSize(_ element: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        
        var size = CGSize.zero
        if AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }
    
    /// Simulates a mouse click at the specified screen position
    private func simulateClick(at point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Mouse down
        guard let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        mouseDown.post(tap: .cghidEventTap)
        
        // Mouse up
        guard let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        mouseUp.post(tap: .cghidEventTap)
        
        return true
    }
    
    /// Scans for and focuses the best matching input field
    /// - Returns: True if a field was found and focused
    @discardableResult
    func scanAndFocus() async -> Bool {
        guard autoFocusEnabled else { return false }
        
        guard let field = await scanForInputField() else {
            return false
        }
        
        return focusField(field)
    }
    
    /// Checks if the current focused element is a text input
    func isFocusedElementTextInput() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedElement = focusedRef else {
            return false
        }
        
        let element = focusedElement as! AXUIElement
        guard let role = getStringAttribute(element, attribute: kAXRoleAttribute) else {
            return false
        }
        
        return inputRoles.contains(role)
    }
    
    // MARK: - Pattern Management
    
    /// Adds a new pattern
    func addPattern(_ pattern: InputFieldPattern) {
        guard !patterns.contains(where: { $0.pattern == pattern.pattern }) else { return }
        patterns.append(pattern)
        saveSettings()
    }
    
    /// Removes a pattern
    func removePattern(_ pattern: InputFieldPattern) {
        patterns.removeAll { $0.pattern == pattern.pattern }
        saveSettings()
    }
    
    /// Updates a pattern
    func updatePattern(_ pattern: InputFieldPattern) {
        if let index = patterns.firstIndex(where: { $0.pattern == pattern.pattern }) {
            patterns[index] = pattern
            saveSettings()
        }
    }
    
    /// Resets patterns to defaults
    func resetPatternsToDefaults() {
        patterns = Self.defaultPatterns
        saveSettings()
    }

    /// Restores all detector settings (patterns + behavior flags) to defaults
    func resetAllSettingsToDefaults() {
        patterns = Self.defaultPatterns
        autoFocusEnabled = true
        UserDefaults.standard.set(true, forKey: "InputFieldAutoFocusSet")
        saveSettings()
    }
    
    // MARK: - Private Methods
    
    /// Recursively scans an element and its children for input fields
    private func scanElement(_ element: AXUIElement, depth: Int, windowTitle: String?, bundleId: String, appName: String) -> [DetectedInputField] {
        guard depth < maxTraversalDepth else { return [] }
        
        var fields: [DetectedInputField] = []
        
        // Check if this element is an input field
        if let role = getStringAttribute(element, attribute: kAXRoleAttribute),
           inputRoles.contains(role) {
            let field = DetectedInputField(
                element: element,
                role: role,
                placeholder: getStringAttribute(element, attribute: kAXPlaceholderValueAttribute),
                value: getStringAttribute(element, attribute: kAXValueAttribute),
                title: getStringAttribute(element, attribute: kAXTitleAttribute) ?? getStringAttribute(element, attribute: kAXDescriptionAttribute),
                windowTitle: windowTitle,
                bundleId: bundleId,
                appName: appName
            )
            fields.append(field)
        }
        
        // Scan children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                let childFields = scanElement(child, depth: depth + 1, windowTitle: windowTitle, bundleId: bundleId, appName: appName)
                fields.append(contentsOf: childFields)
            }
        }
        
        return fields
    }
    
    /// Calculates a confidence score for a detected field
    private func calculateConfidence(for field: DetectedInputField) -> Double {
        var score: Double = 0.0
        let enabledPatterns = patterns.filter { $0.enabled }
        
        for pattern in enabledPatterns {
            let textToMatch: String?
            
            switch pattern.matchType {
            case .placeholder:
                textToMatch = field.placeholder
            case .title:
                textToMatch = field.title
            case .value:
                textToMatch = field.value
            case .any:
                textToMatch = [field.placeholder, field.title, field.value]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }
            
            guard let text = textToMatch else { continue }
            
            if pattern.isRegex {
                if let regex = try? NSRegularExpression(pattern: pattern.pattern, options: .caseInsensitive) {
                    let range = NSRange(text.startIndex..., in: text)
                    if regex.firstMatch(in: text, options: [], range: range) != nil {
                        score += 1.0
                    }
                }
            } else {
                if text.localizedCaseInsensitiveContains(pattern.pattern) {
                    score += 1.0
                }
            }
        }
        
        // Bonus for AXTextArea (usually chat inputs)
        if field.role == "AXTextArea" {
            score += 0.2
        }
        
        // Bonus for empty fields (ready for input)
        if field.value?.isEmpty ?? true {
            score += 0.1
        }
        
        // Normalize score
        let maxPossibleScore = Double(enabledPatterns.count) + 0.3
        return min(score / max(maxPossibleScore, 1.0), 1.0)
    }
    
    /// Gets a string attribute from an accessibility element
    private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }
    
    // MARK: - Persistence
    
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(patterns)
            UserDefaults.standard.set(data, forKey: patternsStorageKey)
        } catch {
            print("Failed to save input field patterns: \(error)")
        }
        UserDefaults.standard.set(autoFocusEnabled, forKey: autoFocusStorageKey)
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: patternsStorageKey) {
            do {
                patterns = try JSONDecoder().decode([InputFieldPattern].self, from: data)
            } catch {
                print("Failed to load input field patterns: \(error)")
            }
        }
        autoFocusEnabled = UserDefaults.standard.bool(forKey: autoFocusStorageKey)
        if !UserDefaults.standard.bool(forKey: "InputFieldAutoFocusSet") {
            autoFocusEnabled = true
            UserDefaults.standard.set(true, forKey: "InputFieldAutoFocusSet")
        }
    }
}
