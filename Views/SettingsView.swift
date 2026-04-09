// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var aiService: AIService

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ThemeSettingsView()
                .tabItem { Label("Theme", systemImage: "paintbrush") }

            AISettingsView(aiService: aiService)
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        #if os(macOS)
        .frame(width: 520, height: 400)
        #endif
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        Form {
            Section("Vault") {
                HStack {
                    Text("Location:").foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Theme

struct ThemeSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        Form {
            Section("Editor Theme") {
                Picker("Theme", selection: $vaultManager.currentTheme) {
                    ForEach(vaultManager.availableThemes) { theme in
                        HStack {
                            Text(theme.name)
                            if !theme.isBuiltIn {
                                Text("(Custom)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(theme.id)
                    }
                }
                .pickerStyle(.inline)

                Text("The selected theme will be applied to the editor immediately.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Custom Themes") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add your own .css theme files to:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(VaultManager.customThemesDirectory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        #if os(macOS)
                        Button("Open") {
                            NSWorkspace.shared.open(VaultManager.customThemesDirectory)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        #endif
                    }

                    Button("Reload Themes") {
                        vaultManager.loadThemes()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            vaultManager.loadThemes()
        }
    }
}

// MARK: - AI

struct AISettingsView: View {
    @ObservedObject var aiService: AIService
    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false
    @State private var ollamaURLInput: String = ""

    var body: some View {
        Form {
            // Provider selection
            Section("AI Provider") {
                Picker("Provider", selection: $aiService.selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(provider.rawValue, systemImage: provider.icon)
                            .tag(provider)
                    }
                }
                .pickerStyle(.inline)
            }

            // Provider-specific settings
            if aiService.selectedProvider == .claude {
                claudeSettings
            } else {
                ollamaSettings
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
        .onAppear {
            apiKeyInput = aiService.claudeAPIKey
            ollamaURLInput = aiService.ollamaURL
        }
    }

    // MARK: - Claude Settings

    private var claudeSettings: some View {
        Section("Claude API") {
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.callout).foregroundStyle(.secondary)

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
                        aiService.claudeAPIKey = apiKeyInput
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(apiKeyInput.isEmpty)
                }
            }

            if !aiService.claudeAPIKey.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("API key is set").font(.callout).foregroundStyle(.secondary)
                }
            }

            Text("Get your API key at console.anthropic.com")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Ollama Settings

    private var ollamaSettings: some View {
        Section("Ollama (Local)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Server URL")
                    .font(.callout).foregroundStyle(.secondary)

                HStack {
                    TextField("http://localhost:11434", text: $ollamaURLInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Button("Save") {
                        aiService.ollamaURL = ollamaURLInput
                        Task { await aiService.fetchOllamaModels() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            }

            // Model selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        Task { await aiService.fetchOllamaModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if aiService.availableOllamaModels.isEmpty {
                    // Manual input if models not fetched
                    TextField("gemma3:27b", text: Binding(
                        get: { aiService.ollamaModel },
                        set: { aiService.ollamaModel = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Text("Enter model name or click Refresh to auto-detect installed models.")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    Picker("", selection: Binding(
                        get: { aiService.ollamaModel },
                        set: { aiService.ollamaModel = $0 }
                    )) {
                        ForEach(aiService.availableOllamaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()

                    Text("\(aiService.availableOllamaModels.count) model(s) found")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }

            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Make sure Ollama is running: `ollama serve`")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
