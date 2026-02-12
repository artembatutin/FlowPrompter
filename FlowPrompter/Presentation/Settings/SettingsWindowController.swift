//
//  SettingsWindowController.swift
//  FlowPrompter
//
//  Created by Artem Batutin on 2026-01-27.
//

import Cocoa
import SwiftUI

@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    
    private var window: NSWindow?
    
    private init() {}
    
    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let dependencies = AppDependencies.shared
        let settingsView = SettingsView(analyticsManager: dependencies.analyticsManager)
            .environmentObject(dependencies.settingsStore)
            .environmentObject(dependencies.permissionsManager)
            .environmentObject(dependencies.modelManager)
            .environmentObject(dependencies.speechRecognizer)
            .environmentObject(dependencies.hotkeyManager)
            .environmentObject(dependencies.sessionManager)
            .environmentObject(dependencies.textInjectionService)
            .environmentObject(dependencies.dictionaryManager)
            .environmentObject(dependencies.inputFieldDetector)
            .environmentObject(dependencies.workspaceScanner)
            .environmentObject(dependencies.fileTagger)
            .environmentObject(dependencies.snippetManager)
            .environmentObject(dependencies.appDataResetManager)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "FlowPrompter Settings"
        newWindow.identifier = NSUserInterfaceItemIdentifier("settings")
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 800, height: 580))
        newWindow.minSize = NSSize(width: 720, height: 520)
        newWindow.center()
        newWindow.setFrameAutosaveName("SettingsWindow")
        newWindow.isReleasedWhenClosed = false
        newWindow.titlebarAppearsTransparent = false
        newWindow.toolbarStyle = .unified
        
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeWindow() {
        window?.close()
    }
}
