// MindMarkCommands.swift
// macOS menu bar commands (⌘N new note, ⌘S save, ⌘⇧O open vault)

import SwiftUI

#if os(macOS)
struct MindMarkCommands: Commands {
    @ObservedObject var vaultManager: VaultManager

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Note") {
                NotificationCenter.default.post(name: .createNewNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Open Vault...") {
                vaultManager.selectVault()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                vaultManager.saveCurrentNote()
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(vaultManager.selectedNote == nil)
        }
    }
}

extension Notification.Name {
    static let createNewNote = Notification.Name("createNewNote")
}
#endif
