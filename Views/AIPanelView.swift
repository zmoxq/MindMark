// AIPanel.swift
// Floating AI action panel for processing selected or full note text

import SwiftUI

struct AIPanelView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @ObservedObject var aiService: AIService
    @Binding var isPresented: Bool

    @State private var customPrompt: String = ""
    @State private var selectedAction: AIAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.indigo)
                Text("AI Assistant")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if aiService.isProcessing {
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Processing...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding()
            } else if !aiService.lastResult.isEmpty, let action = selectedAction {
                // Result view
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(action.rawValue, systemImage: action.icon)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") {
                            copyToClipboard(aiService.lastResult)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Replace") {
                            replaceContent(with: aiService.lastResult)
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.small)
                    }

                    ScrollView {
                        Text(aiService.lastResult)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)

                    Button("Back to actions") {
                        aiService.lastResult = ""
                        selectedAction = nil
                    }
                    .font(.callout)
                }
                .padding()
            } else {
                // Action buttons
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Quick actions
                        SectionHeader(title: "Write")
                        ActionButton(action: .summarize, aiService: aiService, selectedAction: $selectedAction)
                        ActionButton(action: .expand, aiService: aiService, selectedAction: $selectedAction)
                        ActionButton(action: .simplify, aiService: aiService, selectedAction: $selectedAction)
                        ActionButton(action: .fixGrammar, aiService: aiService, selectedAction: $selectedAction)

                        SectionHeader(title: "Translate")
                        ActionButton(action: .translateEnglish, aiService: aiService, selectedAction: $selectedAction)
                        ActionButton(action: .translateChinese, aiService: aiService, selectedAction: $selectedAction)
                        ActionButton(action: .translateFrench, aiService: aiService, selectedAction: $selectedAction)
                        ActionButton(action: .translateSpanish, aiService: aiService, selectedAction: $selectedAction)

                        SectionHeader(title: "Custom")

                        HStack {
                            TextField("Ask AI anything about this note...", text: $customPrompt)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .onSubmit { runFreeform() }

                            Button(action: runFreeform) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.indigo)
                            }
                            .buttonStyle(.plain)
                            .disabled(customPrompt.isEmpty)
                        }
                        .padding(10)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                }

                // Error display
                if let error = aiService.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400)
        #endif
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
    }

    private func runFreeform() {
        guard !customPrompt.isEmpty else { return }
        selectedAction = .freeform
        Task {
            let _ = await aiService.process(
                text: vaultManager.currentMarkdown,
                action: .freeform,
                customPrompt: customPrompt
            )
        }
    }

    private func replaceContent(with text: String) {
        // Send the AI result back as new content
        vaultManager.currentMarkdown = text
        vaultManager.isDirty = true
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

struct ActionButton: View {
    let action: AIAction
    @ObservedObject var aiService: AIService
    @Binding var selectedAction: AIAction?
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        Button {
            selectedAction = action
            Task {
                let _ = await aiService.process(
                    text: vaultManager.currentMarkdown,
                    action: action
                )
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .frame(width: 20)
                    .foregroundStyle(.indigo)
                Text(action.rawValue)
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
