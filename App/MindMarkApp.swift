// MindMarkApp.swift
// MindMark — Notion-style editor, plain Markdown files, you own your data.

import SwiftUI

@main
struct MindMarkApp: App {
    @StateObject private var vaultManager = VaultManager()
    @StateObject private var aiService = AIService()

    var body: some Scene {
        #if os(macOS)
        Window("MindMark", id: "main") {
            ContentView()
                .environmentObject(vaultManager)
                .environmentObject(aiService)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            MindMarkCommands(vaultManager: vaultManager)
        }

        Settings {
            SettingsView()
                .environmentObject(vaultManager)
                .environmentObject(aiService)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(vaultManager)
                .environmentObject(aiService)
        }
        #endif
    }
}
