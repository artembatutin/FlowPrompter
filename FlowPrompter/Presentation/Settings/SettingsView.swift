//
//  SettingsView.swift
//  FlowPrompter
//
//  Created by Artem Batutin on 2026-01-27.
//

import SwiftUI

// MARK: - Settings Navigation

enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case general = "General"
    case hotkeys = "Hotkeys"
    case models = "Models"
    case injection = "Injection"
    case autoFocus = "Auto-Focus"
    case overlay = "Overlay"
    case history = "History"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case fileTagging = "File Tagging"
    case permissions = "Permissions"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .general: return "gear"
        case .hotkeys: return "keyboard"
        case .models: return "cpu"
        case .injection: return "text.cursor"
        case .autoFocus: return "target"
        case .overlay: return "rectangle.on.rectangle"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "book.closed"
        case .snippets: return "doc.text"
        case .fileTagging: return "at"
        case .permissions: return "lock.shield"
        }
    }
    
    var category: SettingsCategory {
        switch self {
        case .dashboard:
            return .overview
        case .general, .hotkeys, .models:
            return .general
        case .injection, .autoFocus, .overlay:
            return .behavior
        case .history, .dictionary, .snippets, .fileTagging:
            return .content
        case .permissions:
            return .system
        }
    }
}

enum SettingsCategory: String, CaseIterable {
    case overview = "Overview"
    case general = "General"
    case behavior = "Behavior"
    case content = "Content"
    case system = "System"
    
    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.category == self }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var permissionsManager: PermissionsManager
    @ObservedObject var analyticsManager: AnalyticsManager
    
    @State private var selectedSection: SettingsSection = .dashboard
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 720, minHeight: 520)
        .frame(idealWidth: 800, idealHeight: 580)
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        List(selection: $selectedSection) {
            ForEach(SettingsCategory.allCases, id: \.self) { category in
                Section {
                    ForEach(category.sections) { section in
                        sidebarRow(for: section)
                            .tag(section)
                    }
                } header: {
                    if category != .overview {
                        Text(category.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    }
    
    private func sidebarRow(for section: SettingsSection) -> some View {
        Label {
            Text(section.rawValue)
        } icon: {
            Image(systemName: section.icon)
                .foregroundColor(section == .dashboard ? .accentColor : .secondary)
        }
    }
    
    // MARK: - Detail View
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:
            UsageDashboardView(analyticsManager: analyticsManager)
        case .general:
            GeneralSettingsView()
        case .hotkeys:
            HotkeySettingsView()
        case .models:
            ModelSettingsView()
        case .injection:
            InjectionSettingsView()
        case .autoFocus:
            InputFieldSettingsView()
        case .overlay:
            OverlaySettingsView()
        case .history:
            HistorySettingsView()
        case .dictionary:
            DictionarySettingsView()
        case .snippets:
            SnippetsSettingsView()
        case .fileTagging:
            FileTaggingSettingsView()
        case .permissions:
            PermissionsSettingsView()
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var appDataResetManager: AppDataResetManager
    
    @State private var showCacheClearConfirmation = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settingsStore.launchAtLogin)
                Toggle("Play Feedback Sounds", isOn: $settingsStore.playFeedbackSounds)
                Toggle("Show Overlay", isOn: $settingsStore.showOverlay)
            } header: {
                Text("General")
            }
            
            Section {
                Toggle("Save History", isOn: $settingsStore.saveHistory)
                
                if settingsStore.saveHistory {
                    Stepper("Max History Items: \(settingsStore.maxHistoryItems)",
                            value: $settingsStore.maxHistoryItems,
                            in: 10...500,
                            step: 10)
                }
            } header: {
                Text("History")
            }

            Section {
                Toggle("Enable Syntax Transformations", isOn: $settingsStore.syntaxTransformEnabled)

                Toggle("Case Transformations", isOn: $settingsStore.caseTransformationsEnabled)
                    .disabled(!settingsStore.syntaxTransformEnabled)

                Toggle("CLI Patterns", isOn: $settingsStore.cliPatternsEnabled)
                    .disabled(!settingsStore.syntaxTransformEnabled)

                Picker("Code Symbols", selection: Binding(
                    get: { settingsStore.codeSymbolsMode },
                    set: { settingsStore.codeSymbolsMode = $0 }
                )) {
                    ForEach(CodeSymbolsMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .disabled(!settingsStore.syntaxTransformEnabled)

                Text(settingsStore.codeSymbolsMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Syntax")
            }
            
            Section {
                Button("Reset to Defaults") {
                    settingsStore.resetToDefaults()
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        showCacheClearConfirmation = true
                    } label: {
                        if appDataResetManager.isClearing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Clearing…")
                            }
                        } else {
                            Text("Clear All App Data")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(appDataResetManager.isClearing)
                    .accessibilityIdentifier("clearAllAppDataButton")
                    
                    Text("Removes cached downloads, history, snippets, dictionary entries, and resets every FlowPrompter setting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let lastClearedAt = appDataResetManager.lastClearedAt {
                        Text("Last cleared: \(lastClearedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let error = appDataResetManager.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Clear All App Data?", isPresented: $showCacheClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await appDataResetManager.clearAllData()
                }
            }
        } message: {
            Text("This removes every locally stored FlowPrompter file and preference. The action cannot be undone.")
        }
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    @State private var selectedPreset: HotkeyPreset = .fn
    @State private var showConflictWarning: Bool = false
    
    var body: some View {
        Form {
            Section {
                Picker("Trigger Mode", selection: Binding(
                    get: { settingsStore.triggerMode },
                    set: { settingsStore.triggerMode = $0 }
                )) {
                    ForEach(TriggerMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                
                Text(settingsStore.triggerMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Trigger Mode")
            }
            
            Section {
                // Current hotkey display
                HStack {
                    Text("Current Hotkey")
                    Spacer()
                    HotkeyBadgeView(keyCombo: hotkeyManager.currentKeyCombo)
                }
                
                // Preset selection
                Picker("Preset", selection: $selectedPreset) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { _, newPreset in
                    if newPreset != .custom, let keyCombo = newPreset.keyCombo {
                        if hotkeyManager.checkForConflicts(with: keyCombo) {
                            showConflictWarning = true
                        } else {
                            hotkeyManager.registerPreset(newPreset)
                        }
                    }
                }
                
                // Custom hotkey recorder
                if selectedPreset == .custom {
                    HotkeyRecorderView()
                }
                
                // Status indicator
                HStack {
                    Image(systemName: hotkeyManager.isListening ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(hotkeyManager.isListening ? .green : .red)
                    Text(hotkeyManager.isListening ? "Hotkey active" : "Hotkey inactive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Hotkey")
            }
            
            Section {
                if settingsStore.triggerMode == .pushToTalk {
                    Text("Hold the hotkey to record, release to transcribe and inject text.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Press the hotkey once to start recording, press again to stop and transcribe.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if hotkeyManager.isHotkeyPressed {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.red)
                        Text("Hotkey is currently pressed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text("Instructions")
            }
            
            if let error = hotkeyManager.lastError {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Warning")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            updateSelectedPreset()
        }
        .alert("Hotkey Conflict", isPresented: $showConflictWarning) {
            Button("Use Anyway") {
                if let keyCombo = selectedPreset.keyCombo {
                    hotkeyManager.registerHotkey(keyCombo)
                }
            }
            Button("Cancel", role: .cancel) {
                updateSelectedPreset()
            }
        } message: {
            Text("This hotkey may conflict with system shortcuts or other applications. Using it might cause unexpected behavior.")
        }
    }
    
    private func updateSelectedPreset() {
        let currentCombo = hotkeyManager.currentKeyCombo
        if currentCombo == .fnKey {
            selectedPreset = .fn
        } else if currentCombo == .controlSpace {
            selectedPreset = .controlSpace
        } else if currentCombo == .optionSpace {
            selectedPreset = .optionSpace
        } else {
            selectedPreset = .custom
        }
    }
}

// MARK: - Hotkey Badge View

struct HotkeyBadgeView: View {
    let keyCombo: KeyCombo
    
    var body: some View {
        Text(keyCombo.displayName)
            .font(.system(.body, design: .rounded))
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .cornerRadius(6)
    }
}

// MARK: - Hotkey Recorder View

struct HotkeyRecorderView: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    
    var body: some View {
        HStack {
            Text("Custom Hotkey")
            Spacer()
            
            if hotkeyManager.isRecordingHotkey {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Press keys...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Cancel") {
                        hotkeyManager.cancelRecordingHotkey()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            } else {
                Button("Record Hotkey") {
                    hotkeyManager.startRecordingHotkey { newKeyCombo in
                        // Hotkey recorded and registered
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var speechRecognizer: SpeechRecognizer
    
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: WhisperModel?
    
    var body: some View {
        Form {
            Section {
                ForEach(modelManager.availableModels) { model in
                    ModelRowView(
                        model: model,
                        isSelected: settingsStore.selectedModel == model.name,
                        isDownloaded: modelManager.isModelDownloaded(model),
                        isDownloading: modelManager.currentDownloadingModel == model.name,
                        downloadProgress: modelManager.currentDownloadingModel == model.name ? modelManager.downloadProgress : nil,
                        isModelLoaded: speechRecognizer.currentModelName == model.name && speechRecognizer.isModelLoaded,
                        onSelect: {
                            settingsStore.selectedModel = model.name
                            modelManager.selectModel(model)
                        },
                        onDownload: {
                            Task {
                                try? await modelManager.downloadModel(model)
                            }
                        },
                        onDelete: {
                            modelToDelete = model
                            showDeleteConfirmation = true
                        },
                        onLoad: {
                            Task {
                                try? await speechRecognizer.loadModel(name: model.name)
                            }
                        }
                    )
                }
            } header: {
                Text("Available Models")
            }
            
            Section {
                if speechRecognizer.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading model...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if speechRecognizer.isModelLoaded {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Model '\(speechRecognizer.currentModelName ?? "Unknown")' is loaded and ready")
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("No model loaded. Select and load a model to start transcribing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Status")
            }
            
            Section {
                Text("Models are downloaded on first use. Larger models provide better accuracy but require more memory and processing time.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("English-only models (.en) are faster and more accurate for English speech. Multilingual models support multiple languages.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Info")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    try? modelManager.deleteModel(model)
                }
                modelToDelete = nil
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete '\(model.displayName)'? You can download it again later.")
            }
        }
        .onAppear {
            modelManager.refreshDownloadedModels()
        }
    }
}

struct ModelRowView: View {
    let model: WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double?
    let isModelLoaded: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    let onLoad: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    if isModelLoaded {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(model.sizeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            if isDownloading, let progress = downloadProgress {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if isDownloaded {
                HStack(spacing: 8) {
                    if !isModelLoaded {
                        Button("Load") {
                            onLoad()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    
                    radioButton
                }
            } else {
                HStack(spacing: 8) {
                    Button("Download") {
                        onDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    radioButton
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isDownloaded {
                onSelect()
            }
        }
    }
    
    private var radioButton: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .onTapGesture {
                if isDownloaded {
                    onSelect()
                }
            }
    }
}

// MARK: - Injection Settings

struct InjectionSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-inject after transcription", isOn: $settingsStore.autoInject)
            } header: {
                Text("Behavior")
            }
            
            Section {
                Picker("Injection Mode", selection: Binding(
                    get: { settingsStore.injectionMode },
                    set: { settingsStore.injectionMode = $0 }
                )) {
                    ForEach(InjectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                
                Text(settingsStore.injectionMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if settingsStore.injectionMode == .clipboardPaste || settingsStore.injectionMode == .hybrid {
                    Toggle("Preserve Clipboard Contents", isOn: $settingsStore.preserveClipboard)
                }
            } header: {
                Text("Method")
            }
            
            if settingsStore.injectionMode == .keystrokeSimulation || settingsStore.injectionMode == .hybrid {
                Section {
                    Slider(value: $settingsStore.typingDelay, in: 0.001...0.1, step: 0.001) {
                        Text("Typing Delay: \(String(format: "%.3f", settingsStore.typingDelay))s")
                    }
                } header: {
                    Text("Keystroke Settings")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Input Field Settings

struct InputFieldSettingsView: View {
    @EnvironmentObject var inputFieldDetector: InputFieldDetector
    
    @State private var newPatternText: String = ""
    @State private var newPatternMatchType: InputFieldPattern.MatchType = .placeholder
    @State private var showAddPattern: Bool = false
    @State private var testResult: String?
    @State private var isTestingDetection: Bool = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-focus Input Fields", isOn: $inputFieldDetector.autoFocusEnabled)
                
                Text("Automatically detect and focus input fields (like 'Ask anything') before injecting text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Auto-Focus")
            }
            
            Section {
                ForEach(inputFieldDetector.patterns) { pattern in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.pattern)
                                .fontWeight(.medium)
                            Text(pattern.matchType.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { pattern.enabled },
                            set: { newValue in
                                var updated = pattern
                                updated.enabled = newValue
                                inputFieldDetector.updatePattern(updated)
                            }
                        ))
                        .labelsHidden()
                        
                        Button(role: .destructive) {
                            inputFieldDetector.removePattern(pattern)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                
                if showAddPattern {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Pattern (e.g., 'Ask anything')", text: $newPatternText)
                            .textFieldStyle(.roundedBorder)
                        
                        Picker("Match Type", selection: $newPatternMatchType) {
                            Text("Placeholder").tag(InputFieldPattern.MatchType.placeholder)
                            Text("Title").tag(InputFieldPattern.MatchType.title)
                            Text("Value").tag(InputFieldPattern.MatchType.value)
                            Text("Any").tag(InputFieldPattern.MatchType.any)
                        }
                        .pickerStyle(.segmented)
                        
                        HStack {
                            Button("Add") {
                                if !newPatternText.isEmpty {
                                    let pattern = InputFieldPattern(
                                        pattern: newPatternText,
                                        matchType: newPatternMatchType
                                    )
                                    inputFieldDetector.addPattern(pattern)
                                    newPatternText = ""
                                    showAddPattern = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newPatternText.isEmpty)
                            
                            Button("Cancel") {
                                newPatternText = ""
                                showAddPattern = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button {
                        showAddPattern = true
                    } label: {
                        Label("Add Pattern", systemImage: "plus")
                    }
                }
            } header: {
                Text("Detection Patterns")
            }
            
            Section {
                HStack {
                    Button {
                        Task {
                            isTestingDetection = true
                            if let field = await inputFieldDetector.scanForInputField() {
                                testResult = "Found: \(field.role)\nPlaceholder: \(field.placeholder ?? "none")\nApp: \(field.appName)\nConfidence: \(String(format: "%.0f%%", field.confidence * 100))"
                            } else {
                                testResult = "No matching input field found in the frontmost application."
                            }
                            isTestingDetection = false
                        }
                    } label: {
                        if isTestingDetection {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Test Detection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingDetection)
                    
                    Button("Test Focus") {
                        Task {
                            _ = await inputFieldDetector.scanAndFocus()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Test")
            }
            
            Section {
                Button("Reset to Defaults") {
                    inputFieldDetector.resetPatternsToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Overlay Settings

struct OverlaySettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    
    var body: some View {
        Form {
            Section {
                Toggle("Show Overlay", isOn: $settingsStore.showOverlay)
                
                Text("Display a floating overlay during dictation showing status and transcription preview.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Visibility")
            }
            
            if settingsStore.showOverlay {
                Section {
                    Picker("Position", selection: $settingsStore.overlayPosition) {
                        ForEach(OverlayPosition.allCases, id: \.rawValue) { position in
                            Text(position.displayName).tag(position.rawValue)
                        }
                    }
                } header: {
                    Text("Position")
                }
                
                Section {
                    VStack(alignment: .leading) {
                        Text("Opacity: \(Int(settingsStore.overlayOpacity * 100))%")
                        Slider(value: $settingsStore.overlayOpacity, in: 0.5...1.0, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Size: \(String(format: "%.1fx", settingsStore.overlaySize))")
                        Slider(value: $settingsStore.overlaySize, in: 0.8...1.5, step: 0.1)
                    }
                } header: {
                    Text("Appearance")
                }
                
                Section {
                    VStack(alignment: .leading) {
                        Text("Auto-hide Delay: \(String(format: "%.1f", settingsStore.overlayAutoHideDelay))s")
                        Slider(value: $settingsStore.overlayAutoHideDelay, in: 0.5...5.0, step: 0.5)
                    }
                    
                    Text("How long the overlay stays visible after transcription completes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Behavior")
                }
                
                Section {
                    Toggle("Real-time Streaming", isOn: $settingsStore.streamingTranscriptionEnabled)
                    
                    Text("Display transcription text as you speak, rather than waiting until recording stops.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if settingsStore.streamingTranscriptionEnabled {
                        VStack(alignment: .leading) {
                            Text("Update Interval: \(String(format: "%.1f", settingsStore.streamingChunkDuration))s")
                            Slider(value: $settingsStore.streamingChunkDuration, in: 0.5...2.0, step: 0.25)
                        }
                        
                        Text("How frequently the streaming text is updated. Lower values provide faster feedback but may be less accurate.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Streaming Transcription")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - History Settings

struct HistorySettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var textInjectionService: TextInjectionService
    
    @State private var selectedTab: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("History").tag(0)
                Text("Statistics").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if selectedTab == 0 {
                HistoryView()
            } else {
                StatisticsView()
            }
        }
    }
}

// MARK: - File Tagging Settings

struct FileTaggingSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var workspaceScanner: WorkspaceScanner
    @EnvironmentObject var fileTagger: FileTagger
    
    @State private var testInput: String = ""
    @State private var testOutput: String = ""
    @State private var isScanning: Bool = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable File Tagging", isOn: $settingsStore.fileTaggingEnabled)
                
                Text("Automatically convert spoken file mentions like \"at app delegate\" to @AppDelegate.swift tags in IDEs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("File Tagging")
            }
            
            if settingsStore.fileTaggingEnabled {
                Section {
                    Toggle("Auto-scan Workspace", isOn: $settingsStore.autoScanWorkspace)
                    
                    Text("Automatically scan the workspace for files when recording starts in an IDE.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Workspace Scanning")
                }
                
                Section {
                    HStack {
                        Text("Workspace Files")
                        Spacer()
                        Text("\(workspaceScanner.workspaceFiles.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let root = workspaceScanner.workspaceRoot {
                        HStack {
                            Text("Workspace Root")
                            Spacer()
                            Text(root.lastPathComponent)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    if let lastScan = workspaceScanner.lastScanDate {
                        HStack {
                            Text("Last Scan")
                            Spacer()
                            Text(lastScan, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Button {
                            Task {
                                isScanning = true
                                await workspaceScanner.scanFromFrontmostIDE()
                                isScanning = false
                            }
                        } label: {
                            if isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Scan Now")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isScanning)
                        
                        Button("Clear Cache") {
                            workspaceScanner.clear()
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Workspace Status")
                }
                
                Section {
                    TextField("Test input (e.g., 'at app delegate')", text: $testInput)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Test File Tagging") {
                        testOutput = fileTagger.processFileMentions(testInput)
                    }
                    .buttonStyle(.bordered)
                    .disabled(testInput.isEmpty || workspaceScanner.workspaceFiles.isEmpty)
                    
                    if !testOutput.isEmpty {
                        HStack {
                            Text("Result:")
                            Text(testOutput)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                    }
                    
                    if workspaceScanner.workspaceFiles.isEmpty {
                        Text("Scan a workspace first to test file tagging.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Test")
                }
                
                if !workspaceScanner.workspaceFiles.isEmpty {
                    Section {
                        ForEach(workspaceScanner.workspaceFiles.prefix(10)) { file in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .fontWeight(.medium)
                                Text(file.relativePath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        if workspaceScanner.workspaceFiles.count > 10 {
                            Text("... and \(workspaceScanner.workspaceFiles.count - 10) more files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Scanned Files (Preview)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager
    
    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Microphone",
                    description: "Required to capture audio for transcription",
                    granted: permissionsManager.microphoneGranted
                ) {
                    Task {
                        await permissionsManager.requestMicrophoneAccess()
                    }
                }
                
                permissionRow(
                    title: "Accessibility",
                    description: "Required to inject text into applications",
                    granted: permissionsManager.accessibilityGranted
                ) {
                    permissionsManager.openAccessibilitySettings()
                }
                
                permissionRow(
                    title: "Input Monitoring",
                    description: "Required for global hotkey detection",
                    granted: permissionsManager.inputMonitoringGranted
                ) {
                    permissionsManager.openInputMonitoringSettings()
                }
                
                permissionRow(
                    title: "Speech Recognition",
                    description: "Optional, for Apple Speech Recognition fallback",
                    granted: permissionsManager.speechRecognitionGranted
                ) {
                    Task {
                        await permissionsManager.requestSpeechRecognition()
                    }
                }
            } header: {
                Text("Permissions")
            }
            
            Section {
                Button("Refresh Permissions") {
                    permissionsManager.refreshAllPermissions()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(granted ? .green : .red)
                    Text(title)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !granted {
                Button("Grant") {
                    action()
                }
            }
        }
    }
}

#Preview {
    let settingsStore = SettingsStore()
    let permissionsManager = PermissionsManager()
    let workspaceScanner = WorkspaceScanner()
    SettingsView(analyticsManager: AnalyticsManager())
        .environmentObject(settingsStore)
        .environmentObject(permissionsManager)
        .environmentObject(ModelManager())
        .environmentObject(SpeechRecognizer())
        .environmentObject(HotkeyManager(settingsStore: settingsStore))
        .environmentObject(SessionManager(settingsStore: settingsStore))
        .environmentObject(InputFieldDetector())
        .environmentObject(TextInjectionService(
            textInjector: TextInjector(),
            settingsStore: settingsStore,
            permissionsManager: permissionsManager
        ))
        .environmentObject(workspaceScanner)
        .environmentObject(FileTagger(workspaceScanner: workspaceScanner))
}
