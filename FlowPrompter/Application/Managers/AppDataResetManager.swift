//
//  AppDataResetManager.swift
//  FlowPrompter
//
//  Created by Cascade on 2026-02-12.
//

import Foundation
import Combine

@MainActor
final class AppDataResetManager: ObservableObject {
    @Published private(set) var isClearing: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastClearedAt: Date?
    
    private weak var dependencies: AppDependencies?
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }
    
    func clearAllData() async {
        guard !isClearing else { return }
        isClearing = true
        lastError = nil
        defer { isClearing = false }
        
        do {
            try await performClear()
            lastClearedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    private func performClear() async throws {
        guard let dependencies else { return }
        
        try recreateAppSupportDirectory()
        clearUserDefaults()
        
        // Reset services and in-memory state
        dependencies.streamingTranscriber.cancelStreaming()
        dependencies.speechRecognizer.unloadModel()
        dependencies.correctionLearner.clearRecentCorrections()
        dependencies.workspaceScanner.clear()
        dependencies.adapterRegistry.resetAppConfigs()
        dependencies.fileTagger.resetTagCount()
        dependencies.fileTagger.isEnabled = dependencies.settingsStore.fileTaggingEnabled
        
        // Remove persisted user data
        dependencies.sessionManager.clearHistory()
        dependencies.sessionManager.resetStatistics()
        dependencies.analyticsManager.resetMetrics()
        dependencies.dictionaryManager.clearAll()
        dependencies.snippetManager.clearAll()
        
        // Reset preferences & models
        dependencies.settingsStore.resetToDefaults()
        dependencies.inputFieldDetector.resetAllSettingsToDefaults()
        dependencies.modelManager.refreshDownloadedModels()
    }
    
    private func recreateAppSupportDirectory() throws {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let appDirectory = appSupport.appendingPathComponent("FlowPrompter", isDirectory: true)
        if fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.removeItem(at: appDirectory)
        }
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        let modelsDirectory = appDirectory.appendingPathComponent("Models", isDirectory: true)
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    private func clearUserDefaults() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
    }
}
