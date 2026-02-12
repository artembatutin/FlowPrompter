//
//  AdapterRegistry.swift
//  FlowPrompter
//
//  Created by Artem Batutin on 2026-01-28.
//

import Foundation
import AppKit
import Combine

/// Registry that manages target adapters and selects the appropriate one for injection
@MainActor
final class AdapterRegistry: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var adapters: [any TargetAdapter] = []
    @Published private(set) var appConfigs: [String: AppInjectionConfig] = [:]
    
    // MARK: - Private Properties
    
    private let configStorageKey = "AppInjectionConfigs"
    private let genericAdapter = GenericAdapter()
    
    // MARK: - Initialization
    
    init() {
        registerDefaultAdapters()
        loadAppConfigs()
    }
    
    // MARK: - Adapter Registration
    
    /// Registers the default set of adapters
    private func registerDefaultAdapters() {
        adapters = [
            ClaudeCodeAdapter(),
            IDEAdapter(),
            TerminalAdapter(),
            TextEditorAdapter(),
            genericAdapter
        ]
    }
    
    /// Registers a custom adapter
    func register(_ adapter: any TargetAdapter) {
        adapters.append(adapter)
        adapters.sort { $0.priority > $1.priority }
    }
    
    /// Unregisters an adapter by display name
    func unregister(displayName: String) {
        adapters.removeAll { $0.displayName == displayName }
    }
    
    // MARK: - Adapter Selection
    
    /// Gets the appropriate adapter for the current frontmost application
    func getAdapter() -> any TargetAdapter {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return genericAdapter
        }
        
        return getAdapter(for: bundleId)
    }
    
    /// Gets the appropriate adapter for a specific bundle identifier
    func getAdapter(for bundleId: String) -> any TargetAdapter {
        // Sort by priority (highest first) and find first matching adapter
        let sortedAdapters = adapters.sorted { $0.priority > $1.priority }
        
        for adapter in sortedAdapters {
            if adapter.canHandle(bundleId: bundleId) {
                return adapter
            }
        }
        
        return genericAdapter
    }
    
    /// Gets the adapter display name for a bundle identifier
    func getAdapterName(for bundleId: String) -> String {
        getAdapter(for: bundleId).displayName
    }
    
    // MARK: - Per-App Configuration
    
    /// Gets the configuration for a specific app
    func getConfig(for bundleId: String) -> AppInjectionConfig? {
        appConfigs[bundleId]
    }
    
    /// Sets the configuration for a specific app
    func setConfig(_ config: AppInjectionConfig) {
        appConfigs[config.bundleId] = config
        saveAppConfigs()
    }
    
    /// Removes the configuration for a specific app
    func removeConfig(for bundleId: String) {
        appConfigs.removeValue(forKey: bundleId)
        saveAppConfigs()
    }
    
    /// Clears every stored app configuration
    func resetAppConfigs() {
        appConfigs.removeAll()
        saveAppConfigs()
    }
    
    /// Gets or creates a default config for an app
    func getOrCreateConfig(for bundleId: String, displayName: String) -> AppInjectionConfig {
        if let existing = appConfigs[bundleId] {
            return existing
        }
        
        let adapter = getAdapter(for: bundleId)
        let config = AppInjectionConfig(
            bundleId: bundleId,
            displayName: displayName,
            injectionMode: adapter.preferredMode
        )
        
        setConfig(config)
        return config
    }
    
    // MARK: - Persistence
    
    /// Saves app configurations to UserDefaults
    private func saveAppConfigs() {
        do {
            let data = try JSONEncoder().encode(appConfigs)
            UserDefaults.standard.set(data, forKey: configStorageKey)
        } catch {
            print("Failed to save app configs: \(error)")
        }
    }
    
    /// Loads app configurations from UserDefaults
    private func loadAppConfigs() {
        guard let data = UserDefaults.standard.data(forKey: configStorageKey) else {
            return
        }
        
        do {
            appConfigs = try JSONDecoder().decode([String: AppInjectionConfig].self, from: data)
        } catch {
            print("Failed to load app configs: \(error)")
        }
    }
    
    // MARK: - Utility Methods
    
    /// Gets information about the current frontmost application
    func getFrontmostAppInfo() -> (bundleId: String, name: String, adapter: String)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier,
              let name = frontmostApp.localizedName else {
            return nil
        }
        
        let adapter = getAdapter(for: bundleId)
        return (bundleId, name, adapter.displayName)
    }
    
    /// Lists all registered adapters with their bundle identifiers
    func listAdapters() -> [(name: String, bundleIds: [String], priority: Int)] {
        adapters.map { ($0.displayName, $0.bundleIdentifiers, $0.priority) }
    }
}
