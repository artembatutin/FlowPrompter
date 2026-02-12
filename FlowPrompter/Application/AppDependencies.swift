//
//  AppDependencies.swift
//  FlowPrompter
//
//  Created by Artem Batutin on 2026-01-27.
//

import Foundation
import AppKit
import Combine

@MainActor
class AppDependencies {
    static let shared = AppDependencies()
    
    let settingsStore: SettingsStore
    let permissionsManager: PermissionsManager
    let appState: AppState
    let audioEngine: AudioEngine
    let audioFeedbackManager: AudioFeedbackManager
    let modelManager: ModelManager
    let speechRecognizer: SpeechRecognizer
    let textInjector: TextInjector
    let adapterRegistry: AdapterRegistry
    let textInjectionService: TextInjectionService
    let inputFieldDetector: InputFieldDetector
    let hotkeyManager: HotkeyManager
    let overlayWindowController: OverlayWindowController
    let sessionManager: SessionManager
    let dictionaryManager: DictionaryManager
    let correctionLearner: CorrectionLearner
    let syntaxTransformer: SyntaxTransformer
    let workspaceScanner: WorkspaceScanner
    let fileTagger: FileTagger
    let snippetManager: SnippetManager
    let streamingTranscriber: StreamingTranscriber
    let analyticsManager: AnalyticsManager
    lazy private(set) var appDataResetManager: AppDataResetManager = {
        AppDataResetManager(dependencies: self)
    }()
    private var cancellables = Set<AnyCancellable>()
    
    /// The target application to inject text into (captured when recording starts)
    private var targetApp: NSRunningApplication?

    private func shouldEnableCodeSymbols(for bundleId: String?) -> Bool {
        switch settingsStore.codeSymbolsMode {
        case .off:
            return false
        case .always:
            return true
        case .contextual:
            guard let bundleId else { return false }
            let adapter = adapterRegistry.getAdapter(for: bundleId)
            return adapter is IDEAdapter || adapter is TerminalAdapter || adapter is ClaudeCodeAdapter
        }
    }
    
    private init() {
        self.settingsStore = SettingsStore()
        self.permissionsManager = PermissionsManager()
        self.appState = AppState()
        
        // Configure audio engine with settings
        var audioConfig = AudioEngineConfiguration()
        audioConfig.maxRecordingDuration = settingsStore.maxRecordingDuration
        self.audioEngine = AudioEngine(configuration: audioConfig)
        
        self.audioFeedbackManager = AudioFeedbackManager()
        self.audioFeedbackManager.isEnabled = settingsStore.playFeedbackSounds
        
        // Initialize model manager and speech recognizer
        self.modelManager = ModelManager()
        self.speechRecognizer = SpeechRecognizer()
        
        // Initialize text injection with adapter registry
        self.textInjector = TextInjector()
        self.adapterRegistry = AdapterRegistry()
        self.inputFieldDetector = InputFieldDetector()
        self.textInjectionService = TextInjectionService(
            textInjector: textInjector,
            settingsStore: settingsStore,
            permissionsManager: permissionsManager,
            adapterRegistry: adapterRegistry,
            inputFieldDetector: inputFieldDetector
        )
        
        // Initialize hotkey manager
        self.hotkeyManager = HotkeyManager(settingsStore: settingsStore)
        
        // Initialize overlay window controller
        self.overlayWindowController = OverlayWindowController(
            appState: appState,
            settingsStore: settingsStore
        )
        
        // Initialize session manager
        self.sessionManager = SessionManager(settingsStore: settingsStore)
        
        // Initialize dictionary system
        self.dictionaryManager = DictionaryManager()
        self.correctionLearner = CorrectionLearner()
        self.correctionLearner.dictionaryManager = dictionaryManager
        
        // Initialize file tagging system
        self.workspaceScanner = WorkspaceScanner()
        self.fileTagger = FileTagger(workspaceScanner: workspaceScanner)
        self.fileTagger.isEnabled = settingsStore.fileTaggingEnabled
        
        // Initialize snippet manager
        self.snippetManager = SnippetManager()
        
        // Initialize streaming transcriber
        self.streamingTranscriber = StreamingTranscriber()
        
        // Initialize analytics manager
        self.analyticsManager = AnalyticsManager()

        // Initialize syntax transformer
        self.syntaxTransformer = SyntaxTransformer()
        self.syntaxTransformer.caseTransformationsEnabled = settingsStore.caseTransformationsEnabled
        self.syntaxTransformer.cliPatternsEnabled = settingsStore.cliPatternsEnabled
        self.syntaxTransformer.codeSymbolsEnabled = shouldEnableCodeSymbols(for: nil)
        
        // Set initial model selection from settings
        modelManager.selectModel(byName: settingsStore.selectedModel)
        
        // Set up audio engine callbacks
        setupAudioEngineCallbacks()
        
        // Set up hotkey callbacks
        setupHotkeyCallbacks()
        
        // Set up streaming transcriber with overlay
        overlayWindowController.setStreamingTranscriber(streamingTranscriber)
        
        // Set up audio engine streaming delegate
        setupStreamingDelegate()
    }
    
    private func setupStreamingDelegate() {
        // Create adapter to bridge AudioEngine with StreamingTranscriber
        let adapter = AudioStreamDelegateAdapter(transcriber: streamingTranscriber)
        audioEngine.streamDelegate = adapter
        
        // Store adapter to prevent deallocation
        streamDelegateAdapter = adapter
    }
    
    private var streamDelegateAdapter: AudioStreamDelegateAdapter?
    
    private func setupAudioEngineCallbacks() {
        // Mirror audio level changes into app state for UI bindings
        audioEngine.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.appState.audioLevel = level
            }
            .store(in: &cancellables)

        // Handle auto-stop events
        audioEngine.onAutoStop = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.audioEngine.isRecording {
                    _ = try? self.audioEngine.stopRecording()
                    self.appState.setIdle()
                    self.audioFeedbackManager.playStopSound()
                }
            }
        }
    }
    
    func loadSelectedModel() async {
        let modelName = settingsStore.selectedModel
        if modelManager.isModelDownloaded(WhisperModel.model(forName: modelName) ?? WhisperModel.availableModels[0]) {
            do {
                try await speechRecognizer.loadModel(name: modelName)
                appState.isModelLoaded = true
            } catch {
                appState.isModelLoaded = false
                appState.setError("Failed to load model: \(error.localizedDescription)")
            }
        }
    }
    
    private func setupHotkeyCallbacks() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.startRecording()
            }
        }
        
        hotkeyManager.onHotkeyReleased = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.stopRecordingAndTranscribe()
            }
        }
        
        hotkeyManager.onToggleActivated = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Toggle mode state is handled by onHotkeyPressed/onHotkeyReleased
            }
        }
    }
    
    private func startRecording() {
        guard permissionsManager.microphoneGranted else {
            appState.setError("Microphone permission not granted")
            return
        }
        
        guard appState.isModelLoaded else {
            appState.setError("No model loaded. Please load a model first.")
            return
        }
        
        // Capture the target app BEFORE we start recording
        // This is the app that will receive the transcribed text
        targetApp = textInjector.getFrontmostApp()
        
        // Scan workspace if file tagging is enabled and we're in an IDE
        if settingsStore.fileTaggingEnabled && settingsStore.autoScanWorkspace {
            if let bundleId = targetApp?.bundleIdentifier,
               adapterRegistry.getAdapter(for: bundleId).displayName == "IDE" {
                Task {
                    await workspaceScanner.scanFromFrontmostIDE()
                }
            }
        }
        
        do {
            try audioEngine.startRecording()
            appState.setListening()
            audioFeedbackManager.playStartSound()
            sessionManager.startSession()
            
            // Start streaming transcription if enabled
            if settingsStore.streamingTranscriptionEnabled {
                Task {
                    await startStreamingTranscription()
                }
            }
        } catch {
            appState.setError("Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    private func startStreamingTranscription() async {
        // Ensure WhisperKit is available for streaming
        if let whisperKit = speechRecognizer.whisperKit {
            streamingTranscriber.setWhisperKit(whisperKit)
            do {
                try await streamingTranscriber.startStreaming()
            } catch {
                // Silently fail - streaming is optional enhancement
            }
        }
    }
    
    private func stopRecordingAndTranscribe() async {
        guard audioEngine.isRecording else { return }
        
        // Stop streaming transcription first
        let streamedText = await streamingTranscriber.stopStreaming()
        
        do {
            let audioBuffer = try audioEngine.stopRecording()
            appState.setProcessing()
            audioFeedbackManager.playStopSound()
            
            if let buffer = audioBuffer {
                let result = try await speechRecognizer.transcribe(audioBuffer: buffer)
                var transcription = result.text
                
                // Apply personal dictionary replacements if enabled
                if settingsStore.dictionaryEnabled {
                    transcription = dictionaryManager.applyDictionary(to: transcription)
                }
                
                // Apply syntax transformations if enabled
                if settingsStore.syntaxTransformEnabled {
                    // Sync settings with transformer
                    syntaxTransformer.caseTransformationsEnabled = settingsStore.caseTransformationsEnabled
                    syntaxTransformer.cliPatternsEnabled = settingsStore.cliPatternsEnabled
                    syntaxTransformer.codeSymbolsEnabled = shouldEnableCodeSymbols(for: targetApp?.bundleIdentifier)
                    transcription = syntaxTransformer.transform(transcription)
                }
                
                // Apply file tagging if enabled and in an IDE
                if settingsStore.fileTaggingEnabled {
                    fileTagger.isEnabled = true
                    transcription = fileTagger.processFileMentions(transcription)
                }
                
                // Apply snippet expansion if enabled
                if settingsStore.snippetsEnabled {
                    let bundleId = targetApp?.bundleIdentifier
                    transcription = snippetManager.processText(transcription, bundleId: bundleId)
                }
                
                appState.updateTranscription(transcription)
                
                if settingsStore.autoInject && !transcription.isEmpty {
                    // Restore focus to the target app before injection
                    if let target = targetApp {
                        textInjector.activateApp(target)
                        // Brief delay to allow focus to switch
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    }
                    
                    // Auto-focus input field if enabled
                    if inputFieldDetector.autoFocusEnabled {
                        let focusSuccess = await inputFieldDetector.scanAndFocus()
                        // Longer delay after focusing to ensure click registers
                        try await Task.sleep(nanoseconds: focusSuccess ? 150_000_000 : 50_000_000) // 150ms if focused, 50ms otherwise
                    }
                    
                    try await textInjectionService.inject(text: transcription)
                    
                    // Record injection for correction learning if enabled
                    if settingsStore.autoLearnCorrections {
                        correctionLearner.recordInjection(transcription)
                    }
                }
                
                // Save session to history and record analytics
                if !transcription.isEmpty {
                    let session = TranscriptionSession(
                        transcription: transcription,
                        targetApp: targetApp?.localizedName,
                        duration: Date().timeIntervalSince(sessionManager.currentSessionStartTime ?? Date()),
                        modelUsed: settingsStore.selectedModel
                    )
                    
                    sessionManager.endSession(
                        transcription: transcription,
                        modelUsed: settingsStore.selectedModel
                    )
                    
                    // Record to analytics
                    analyticsManager.recordSession(session)
                }
            }
            
            setIdleIfNotRecording()
        } catch {
            appState.setError("Transcription failed: \(error.localizedDescription)")
            setIdleIfNotRecording()
        }
    }

    private func setIdleIfNotRecording() {
        guard !audioEngine.isRecording else { return }
        appState.setIdle()
    }
    
    func startHotkeyListening() {
        guard permissionsManager.inputMonitoringGranted || permissionsManager.accessibilityGranted else {
            return
        }
        hotkeyManager.startListening()
    }
    
    func stopHotkeyListening() {
        hotkeyManager.stopListening()
    }
}
