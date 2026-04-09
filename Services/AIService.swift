// AIService.swift
// Multi-provider AI integration: Anthropic Claude, Ollama (local models)

import SwiftUI
import Combine

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude (Anthropic)"
    case ollama = "Ollama (Local)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .claude: return "cloud"
        case .ollama: return "desktopcomputer"
        }
    }
}

// MARK: - AI Action Types

enum AIAction: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case expand = "Expand"
    case simplify = "Simplify"
    case fixGrammar = "Fix Grammar"
    case translateEnglish = "Translate to English"
    case translateChinese = "Translate to Chinese"
    case translateFrench = "Translate to French"
    case translateSpanish = "Translate to Spanish"
    case freeform = "Ask AI..."

    var id: String { rawValue }

    var systemPrompt: String {
        switch self {
        case .summarize:
            return "Summarize the following text concisely. Keep key points and structure. Respond in the same language as the input."
        case .expand:
            return "Expand the following text with more details, examples, and explanations. Maintain the same style and language."
        case .simplify:
            return "Simplify the following text. Use shorter sentences and simpler words. Keep the meaning intact. Respond in the same language."
        case .fixGrammar:
            return "Fix grammar, spelling, and punctuation in the following text. Keep the meaning and style unchanged. Only output the corrected text."
        case .translateEnglish:
            return "Translate the following text to English. Preserve formatting and markdown syntax."
        case .translateChinese:
            return "Translate the following text to Simplified Chinese. Preserve formatting and markdown syntax."
        case .translateFrench:
            return "Translate the following text to French. Preserve formatting and markdown syntax."
        case .translateSpanish:
            return "Translate the following text to Spanish. Preserve formatting and markdown syntax."
        case .freeform:
            return "You are a helpful writing assistant. The user will give you text and a request. Help them with their request. Respond in markdown format."
        }
    }

    var icon: String {
        switch self {
        case .summarize: return "text.justify.left"
        case .expand: return "text.append"
        case .simplify: return "text.badge.minus"
        case .fixGrammar: return "textformat.abc"
        case .translateEnglish, .translateChinese, .translateFrench, .translateSpanish: return "globe"
        case .freeform: return "sparkles"
        }
    }
}

// MARK: - AI Response

struct AIResponse {
    let text: String
    let action: AIAction
}

// MARK: - AI Service

class AIService: ObservableObject {
    @Published var isProcessing: Bool = false
    @Published var lastResult: String = ""
    @Published var lastError: String?

    // Provider selection
    @Published var selectedProvider: AIProvider {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "aiProvider") }
    }

    // Claude settings
    var claudeAPIKey: String {
        get { UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "anthropicAPIKey") }
    }

    var claudeModel: String {
        get { UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-4-20250514" }
        set { UserDefaults.standard.set(newValue, forKey: "claudeModel") }
    }

    // Ollama settings
    var ollamaURL: String {
        get { UserDefaults.standard.string(forKey: "ollamaURL") ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaURL") }
    }

    var ollamaModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "gemma3:27b" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    @Published var availableOllamaModels: [String] = []

    // Convenience
    var hasAPIKey: Bool {
        switch selectedProvider {
        case .claude: return !claudeAPIKey.isEmpty
        case .ollama: return true  // No API key needed for local
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "aiProvider") ?? ""
        selectedProvider = AIProvider(rawValue: saved) ?? .claude
    }

    // MARK: - Process

    func process(text: String, action: AIAction, customPrompt: String? = nil) async -> AIResponse? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run { lastError = "No text to process." }
            return nil
        }

        await MainActor.run { isProcessing = true; lastError = nil }

        let userMessage: String
        if action == .freeform, let prompt = customPrompt {
            userMessage = "Here is the text:\n\n\(text)\n\nRequest: \(prompt)"
        } else {
            userMessage = text
        }

        do {
            let result: String
            switch selectedProvider {
            case .claude:
                guard !claudeAPIKey.isEmpty else {
                    await MainActor.run { isProcessing = false; lastError = "Please set your Claude API key." }
                    return nil
                }
                result = try await callClaude(systemPrompt: action.systemPrompt, userMessage: userMessage)
            case .ollama:
                result = try await callOllama(systemPrompt: action.systemPrompt, userMessage: userMessage)
            }

            await MainActor.run {
                isProcessing = false
                lastResult = result
            }
            return AIResponse(text: result, action: action)
        } catch {
            await MainActor.run {
                isProcessing = false
                lastError = error.localizedDescription
            }
            return nil
        }
    }

    // MARK: - Claude API

    private func callClaude(systemPrompt: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": claudeModel,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError(statusCode: code, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIError.parseError
        }
        return text
    }

    // MARK: - Ollama API (OpenAI-compatible)

    private func callOllama(systemPrompt: String, userMessage: String) async throws -> String {
        let endpoint = "\(ollamaURL)/api/chat"
        guard let url = URL(string: endpoint) else {
            throw AIError.apiError(statusCode: 0, message: "Invalid Ollama URL: \(endpoint)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120  // Local models can be slow

        let body: [String: Any] = [
            "model": ollamaModel,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError(statusCode: code, message: "Ollama error (\(code)): \(errorBody)")
        }

        // Ollama /api/chat response format: { "message": { "content": "..." } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parseError
        }
        return content
    }

    // MARK: - Ollama Model Discovery

    func fetchOllamaModels() async {
        let endpoint = "\(ollamaURL)/api/tags"
        guard let url = URL(string: endpoint) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return }

            let names = models.compactMap { $0["name"] as? String }.sorted()
            await MainActor.run {
                availableOllamaModels = names
                if !names.isEmpty && !names.contains(ollamaModel) {
                    ollamaModel = names.first ?? "gemma3:27b"
                }
            }
        } catch {
            print("[AI] Failed to fetch Ollama models: \(error)")
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from API"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .parseError: return "Failed to parse API response"
        }
    }
}
