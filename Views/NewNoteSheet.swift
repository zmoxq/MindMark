// NewNoteSheet.swift
// Template picker sheet for creating new notes

import SwiftUI

struct NewNoteSheet: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Environment(\.dismiss) private var dismiss

    @State private var noteName: String = ""
    @State private var selectedTemplate: NoteTemplate = .default
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Note")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Untitled", text: $noteName)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNameFocused)
                        .onSubmit { createNote() }
                }

                // Template picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Template")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(NoteTemplate.allCases) { template in
                        Button {
                            selectedTemplate = template
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.icon)
                                    .font(.title2)
                                    .foregroundStyle(template.accentColor)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedTemplate == template {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.indigo)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTemplate == template ? Color.indigo.opacity(0.08) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedTemplate == template ? Color.indigo.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()

            Spacer()

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Create") { createNote() }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .keyboardShortcut(.defaultAction)
                    .disabled(noteName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        #if os(macOS)
        .frame(width: 420, height: 400)
        #endif
        .onAppear {
            isNameFocused = true
        }
    }

    private func createNote() {
        let name = noteName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        vaultManager.createNote(name: name, template: selectedTemplate)
        dismiss()
    }
}
