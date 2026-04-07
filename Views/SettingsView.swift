// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var aiService: AIService

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            AISettingsView(aiService: aiService)
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        #if os(macOS)
        .frame(width: 500, height: 360)
        #endif
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text("Location:")
                        .foregroundStyle(.secondary)
                    Text(vaultManager.vaultURL?.path ?? "None")
                        .lineLimit(1).truncationMode(.head)
                    Spacer()
                    #if os(macOS)
                    Button("Change...") { vaultManager.selectVault() }
                    #endif
                }

                if vaultManager.vaultURL != nil {
                    let count = vaultManager.allNotes().count
                    HStack {
                        Text("Notes:").foregroundStyle(.secondary)
                        Text("\(count) file\(count == 1 ? "" : "s")")
                    }

                    Text("Tip: Place your vault in Dropbox, iCloud Drive, or Google Drive to sync across devices.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            Section("Editor") {
                Text("Theme and editor settings coming soon...")
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AISettingsView: View {
    @ObservedObject var aiService: AIService
    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false

    var body: some View {
        Form {
            Section("Anthropic Claude API") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)

                        Button("Save") {
                            aiService.apiKey = apiKeyInput
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(apiKeyInput.isEmpty)
                    }
                }
                .onAppear {
                    apiKeyInput = aiService.apiKey
                }

                if aiService.hasAPIKey {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API key is set")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Text("Enter your API key to enable AI features")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Get your API key at console.anthropic.com\nYour key is stored locally and never shared.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("AI Features") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Summarize, expand, or simplify text", systemImage: "text.justify.left")
                    Label("Fix grammar and spelling", systemImage: "textformat.abc")
                    Label("Translate to multiple languages", systemImage: "globe")
                    Label("Ask questions about your notes", systemImage: "sparkles")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
