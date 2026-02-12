//
//  AudioEngine.swift
//  FlowPrompter
//
//  Created by Artem Batutin on 2026-01-27.
//

import Foundation
import AVFoundation
import Combine

enum AudioEngineError: LocalizedError {
    case permissionDenied
    case engineStartFailed(Error)
    case noInputNode
    case formatConversionFailed
    case recordingInProgress
    case notRecording
    case maxDurationReached
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputNode:
            return "No audio input device available"
        case .formatConversionFailed:
            return "Failed to convert audio format"
        case .recordingInProgress:
            return "Recording is already in progress"
        case .notRecording:
            return "Not currently recording"
        case .maxDurationReached:
            return "Maximum recording duration reached"
        }
    }
}

/// Configuration for the audio engine
struct AudioEngineConfiguration {
    /// Sample rate for Whisper (16kHz)
    let sampleRate: Double = 16000.0
    /// Mono channel for Whisper
    let channelCount: AVAudioChannelCount = 1
    /// Maximum recording duration in seconds
    var maxRecordingDuration: TimeInterval = 120.0
    /// Enable silence detection
    var silenceDetectionEnabled: Bool = false
    /// Silence threshold (0.0 - 1.0)
    var silenceThreshold: Float = 0.01
    /// Duration of silence before auto-stop (seconds)
    var silenceDuration: TimeInterval = 2.0
}

@MainActor
class AudioEngine: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var recordingDuration: TimeInterval = 0.0
    @Published private(set) var error: AudioEngineError?
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffers: [AVAudioPCMBuffer] = []
    private var configuration: AudioEngineConfiguration
    
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var silenceStartTime: Date?
    
    private var levelUpdateTask: Task<Void, Never>?
    
    // Callback for when max duration or silence auto-stop triggers
    var onAutoStop: (() -> Void)?
    
    // Delegate for streaming audio samples
    weak var streamDelegate: AudioStreamDelegate?
    
    // MARK: - Initialization
    
    init(configuration: AudioEngineConfiguration = AudioEngineConfiguration()) {
        self.configuration = configuration
        setupNotifications()
    }
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
    
    // MARK: - Public Methods
    
    /// Request microphone permission
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    /// Start recording audio
    func startRecording() throws {
        guard !isRecording else {
            throw AudioEngineError.recordingInProgress
        }
        
        // Check permission
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            throw AudioEngineError.permissionDenied
        }
        
        // Initialize engine
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        self.inputNode = inputNode
        
        // Get the native format and configure converter
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        
        guard nativeFormat.sampleRate > 0 else {
            throw AudioEngineError.noInputNode
        }
        
        // Target format for Whisper: 16kHz, mono, Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: configuration.sampleRate,
            channels: configuration.channelCount,
            interleaved: false
        ) else {
            throw AudioEngineError.formatConversionFailed
        }
        
        // Create format converter if needed
        let converter: AVAudioConverter?
        if nativeFormat.sampleRate != configuration.sampleRate || nativeFormat.channelCount != configuration.channelCount {
            converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        } else {
            converter = nil
        }
        
        // Clear previous buffers
        audioBuffers.removeAll()
        error = nil
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, time in
            guard let bufferCopy = buffer.makeCopy() else { return }
            Task { @MainActor [weak self] in
                self?.processAudioBuffer(bufferCopy, converter: converter, targetFormat: targetFormat)
            }
        }
        
        // Prepare and start engine
        engine.prepare()
        
        do {
            try engine.start()
        } catch {
            cleanup()
            throw AudioEngineError.engineStartFailed(error)
        }
        
        // Update state
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0.0
        silenceStartTime = nil
        
        // Start duration timer
        startDurationTimer()
    }
    
    /// Stop recording and return accumulated audio buffer
    func stopRecording() throws -> AVAudioPCMBuffer? {
        guard isRecording else {
            throw AudioEngineError.notRecording
        }
        
        // Stop timer
        stopDurationTimer()
        
        // Remove tap and stop engine
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        
        // Update state
        isRecording = false
        audioLevel = 0.0
        
        // Combine all buffers into one
        let combinedBuffer = combineBuffers()
        
        // Cleanup
        audioBuffers.removeAll()
        audioEngine = nil
        inputNode = nil
        
        return combinedBuffer
    }
    
    /// Update configuration
    func updateConfiguration(_ config: AudioEngineConfiguration) {
        self.configuration = config
    }
    
    // MARK: - Private Methods
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        guard isRecording else { return }
        
        let processedBuffer: AVAudioPCMBuffer
        
        if let converter = converter {
            // Convert to target format
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (configuration.sampleRate / buffer.format.sampleRate)
            )
            
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else {
                return
            }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, error == nil else {
                return
            }
            
            processedBuffer = convertedBuffer
        } else {
            processedBuffer = buffer
        }
        
        // Store buffer
        audioBuffers.append(processedBuffer)
        
        // Forward samples to stream delegate for real-time transcription
        if let samples = processedBuffer.toFloatArray()?.map({ max(-1.0, min(1.0, $0)) }) {
            streamDelegate?.audioEngine(self, didCaptureSamples: samples)
        }
        
        // Calculate audio level
        updateAudioLevel(from: processedBuffer)
        
        // Check silence detection
        if configuration.silenceDetectionEnabled {
            checkSilence()
        }
    }
    
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        // Convert to 0-1 range with some scaling for better visualization
        let normalizedLevel = min(1.0, rms * 5.0)
        
        // Smooth the level update
        audioLevel = audioLevel * 0.7 + normalizedLevel * 0.3
    }
    
    private func checkSilence() {
        if audioLevel < configuration.silenceThreshold {
            if silenceStartTime == nil {
                silenceStartTime = Date()
            } else if let start = silenceStartTime,
                      Date().timeIntervalSince(start) >= configuration.silenceDuration {
                // Auto-stop due to silence
                Task { @MainActor in
                    onAutoStop?()
                }
            }
        } else {
            silenceStartTime = nil
        }
    }
    
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                
                self.recordingDuration = Date().timeIntervalSince(startTime)
                
                // Check max duration
                if self.recordingDuration >= self.configuration.maxRecordingDuration {
                    self.error = .maxDurationReached
                    self.onAutoStop?()
                }
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    private func combineBuffers() -> AVAudioPCMBuffer? {
        guard !audioBuffers.isEmpty else { return nil }
        
        // Calculate total frame count
        let totalFrames = audioBuffers.reduce(0) { $0 + $1.frameLength }
        
        guard totalFrames > 0,
              let format = audioBuffers.first?.format,
              let combinedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return nil
        }
        
        combinedBuffer.frameLength = totalFrames
        
        guard let destinationPointer = combinedBuffer.floatChannelData?[0] else {
            return nil
        }
        
        var offset: AVAudioFrameCount = 0
        
        for buffer in audioBuffers {
            guard let sourcePointer = buffer.floatChannelData?[0] else { continue }
            
            let frameCount = buffer.frameLength
            destinationPointer.advanced(by: Int(offset)).update(from: sourcePointer, count: Int(frameCount))
            offset += frameCount
        }
        
        return combinedBuffer
    }
    
    private func cleanup() {
        stopDurationTimer()
        levelUpdateTask?.cancel()
        
        if isRecording {
            inputNode?.removeTap(onBus: 0)
            audioEngine?.stop()
        }
        
        audioBuffers.removeAll()
        audioEngine = nil
        inputNode = nil
        isRecording = false
        audioLevel = 0.0
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // On macOS, we listen for audio engine configuration changes
        // which occur when audio devices are connected/disconnected
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleConfigurationChange(notification)
            }
        }
        
        // Listen for default audio device changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AVAudioDeviceDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDeviceChange()
            }
        }
    }
    
    private func handleConfigurationChange(_ notification: Notification) {
        // Handle audio device changes - the engine configuration changed
        if isRecording {
            // Stop and notify - let the caller decide whether to restart
            onAutoStop?()
        }
    }
    
    private func handleDeviceChange() {
        // Handle audio device changes (e.g., headphones connected/disconnected)
        if isRecording {
            onAutoStop?()
        }
    }
}

// MARK: - Audio Buffer Extension

extension AVAudioPCMBuffer {
    /// Convert buffer to Float array for Whisper processing
    func toFloatArray() -> [Float]? {
        guard let channelData = floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(frameLength)))
    }

    /// Create a deep copy of the buffer so it can be safely used off the audio tap thread
    func makeCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength

        let channels = Int(format.channelCount)

        if let source = floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].assign(from: source[channel], count: Int(frameLength))
            }
            return copy
        }

        if let source = int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].assign(from: source[channel], count: Int(frameLength))
            }
            return copy
        }

        if let source = int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].assign(from: source[channel], count: Int(frameLength))
            }
            return copy
        }

        return nil
    }
}
