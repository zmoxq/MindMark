// EditorWebView.swift
// WKWebView hosting BlockNote — dual format bridge + image upload + file dialog + vault file access

import SwiftUI
import WebKit
#if os(macOS)
import UniformTypeIdentifiers
#endif

// MARK: - macOS

#if os(macOS)
struct EditorWebView: NSViewRepresentable {
    @Binding var markdown: String
    @Binding var blocksJson: String
    var onContentChanged: (String, String) -> Void
    var vaultManager: VaultManager

    func makeCoordinator() -> Coordinator {
        Coordinator(
            markdown: $markdown,
            blocksJson: $blocksJson,
            onContentChanged: onContentChanged,
            vaultManager: vaultManager
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = Self.createWebView(coordinator: context.coordinator)
        context.coordinator.webView = webView
        Self.loadEditor(in: webView, vaultURL: vaultManager.vaultURL)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

// MARK: - iOS

#if os(iOS)
struct EditorWebView: UIViewRepresentable {
    @Binding var markdown: String
    @Binding var blocksJson: String
    var onContentChanged: (String, String) -> Void
    var vaultManager: VaultManager

    func makeCoordinator() -> Coordinator {
        Coordinator(
            markdown: $markdown,
            blocksJson: $blocksJson,
            onContentChanged: onContentChanged,
            vaultManager: vaultManager
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = Self.createWebView(coordinator: context.coordinator)
        context.coordinator.webView = webView
        Self.loadEditor(in: webView, vaultURL: vaultManager.vaultURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

// MARK: - Shared

extension EditorWebView {

    static func createWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(coordinator, name: "mindmark")
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator

        #if os(macOS)
        #if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        webView.setValue(false, forKey: "drawsBackground")
        #endif

        #if os(iOS)
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        #endif

        return webView
    }

    static func loadEditor(in webView: WKWebView, vaultURL: URL?) {
        if let editorURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") {
            // Grant read access to both Editor directory AND vault folder
            // so WKWebView can display images from the attachment folders
            var accessURL = editorURL.deletingLastPathComponent()
            if let vault = vaultURL {
                // Find common ancestor of Editor and vault, or just use root
                // Simplest approach: grant access to the widest needed scope
                accessURL = commonAncestor(editorURL, vault) ?? accessURL
            }
            webView.loadFileURL(editorURL, allowingReadAccessTo: accessURL)
            return
        }

        // Fallback for development
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { font-family: -apple-system, sans-serif; padding: 24px; max-width: 720px; margin: 0 auto; }
            @media (prefers-color-scheme: dark) { body { background: #1a1a2e; color: #e0e0e0; } }
            #editor { outline: none; min-height: 300px; line-height: 1.7; font-size: 16px; }
            #editor:empty::before { content: "Start writing... (BlockNote not bundled)"; color: #999; }
          </style>
        </head>
        <body>
          <div id="editor" contenteditable="true"></div>
          <script>
            window.mindmark = {
              receiveFromSwift: function(action, payload) {
                if (action === 'loadDocument') {
                  document.getElementById('editor').innerText = payload.markdown || '';
                }
                if (action === 'getContent') {
                  window.webkit.messageHandlers.mindmark.postMessage({
                    action: 'requestSave',
                    payload: { markdown: document.getElementById('editor').innerText, blocksJson: '' }
                  });
                }
                if (action === 'newDocument') {
                  document.getElementById('editor').innerText = '';
                }
              }
            };
            try {
              window.webkit.messageHandlers.mindmark.postMessage({ action: 'editorReady', payload: null });
            } catch(e) {}
            document.getElementById('editor').addEventListener('input', function() {
              try {
                window.webkit.messageHandlers.mindmark.postMessage({
                  action: 'contentChanged',
                  payload: { markdown: this.innerText, blocksJson: '' }
                });
              } catch(e) {}
            });
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Find common ancestor directory of two URLs
    private static func commonAncestor(_ a: URL, _ b: URL) -> URL? {
        let aComps = a.pathComponents
        let bComps = b.pathComponents
        var common: [String] = []
        for (ac, bc) in zip(aComps, bComps) {
            if ac == bc { common.append(ac) } else { break }
        }
        guard common.count > 1 else { return URL(fileURLWithPath: "/") }
        let path = common.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
        return URL(fileURLWithPath: path)
    }
}

// MARK: - Coordinator

extension EditorWebView {
    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var webView: WKWebView?
        @Binding var markdown: String
        @Binding var blocksJson: String
        var onContentChanged: (String, String) -> Void
        var vaultManager: VaultManager
        private var isEditorReady = false
        private var pendingLoad: (() -> Void)?

        init(
            markdown: Binding<String>,
            blocksJson: Binding<String>,
            onContentChanged: @escaping (String, String) -> Void,
            vaultManager: VaultManager
        ) {
            _markdown = markdown
            _blocksJson = blocksJson
            self.onContentChanged = onContentChanged
            self.vaultManager = vaultManager
        }

        // MARK: JS → Swift

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }
            let payload = body["payload"] as? [String: Any]

            switch action {
            case "editorReady":
                isEditorReady = true
                if let pending = pendingLoad {
                    pending()
                    pendingLoad = nil
                } else if !blocksJson.isEmpty {
                    loadDocument(blocksJson: blocksJson)
                } else if !markdown.isEmpty {
                    loadDocument(markdown: markdown)
                }

            case "contentChanged", "requestSave":
                let md = payload?["markdown"] as? String ?? ""
                let json = payload?["blocksJson"] as? String ?? ""
                DispatchQueue.main.async {
                    self.markdown = md
                    self.blocksJson = json
                    self.onContentChanged(md, json)
                }

            case "uploadImage":
                handleImageUpload(payload)

            case "focusChanged":
                break

            case "log":
                if let msg = payload?["message"] as? String {
                    print("[Editor] \(msg)")
                }

            default:
                print("[Bridge] Unknown action: \(action)")
            }
        }

        // MARK: Image Upload

        private func handleImageUpload(_ payload: [String: Any]?) {
            guard let requestId = payload?["requestId"] as? String,
                  let base64Data = payload?["base64Data"] as? String,
                  let fileName = payload?["fileName"] as? String else {
                print("[Bridge] Invalid uploadImage payload")
                return
            }

            print("[Bridge] Received image upload: \(fileName) (\(base64Data.count / 1024)KB base64)")

            guard let data = Data(base64Encoded: base64Data) else {
                print("[Bridge] Failed to decode base64 image data")
                sendImageUploadResult(requestId: requestId, relativePath: nil, error: "Invalid base64 data")
                return
            }

            // Detect MIME type from file extension
            let ext = (fileName as NSString).pathExtension.lowercased()
            let mimeType: String
            switch ext {
            case "png": mimeType = "image/png"
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "gif": mimeType = "image/gif"
            case "svg": mimeType = "image/svg+xml"
            case "webp": mimeType = "image/webp"
            case "tiff", "tif": mimeType = "image/tiff"
            default: mimeType = "image/png"
            }

            Task { @MainActor in
                guard let note = vaultManager.selectedNote else {
                    sendImageUploadResult(requestId: requestId, relativePath: nil, error: "No note selected")
                    return
                }

                if let _ = vaultManager.saveAttachment(for: note, data: data, fileName: fileName) {
                    // Return base64 data URL for immediate display in WKWebView
                    // (file:// URLs are blocked by sandbox)
                    let dataURL = "data:\(mimeType);base64,\(base64Data)"
                    sendImageUploadResult(requestId: requestId, relativePath: dataURL, error: nil)
                    print("[Bridge] Image displayed via data URL")
                } else {
                    sendImageUploadResult(requestId: requestId, relativePath: nil, error: "Failed to save attachment")
                }
            }
        }

        private func sendImageUploadResult(requestId: String, relativePath: String?, error: String?) {
            guard let webView = webView else { return }

            let pathStr = relativePath.map { "\"\(escapeForJS($0))\"" } ?? "null"
            let errorStr = error.map { "\"\(escapeForJS($0))\"" } ?? "null"

            let js = """
            window.mindmark.receiveFromSwift('imageUploaded', {
                requestId: "\(escapeForJS(requestId))",
                relativePath: \(pathStr),
                error: \(errorStr)
            })
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { _, err in
                    if let err = err {
                        print("[Bridge] Failed to send imageUploaded: \(err)")
                    }
                }
            }
        }

        // MARK: Swift → JS

        func loadDocument(blocksJson: String) {
            guard isEditorReady, let webView = webView else {
                pendingLoad = { [weak self] in self?.loadDocument(blocksJson: blocksJson) }
                return
            }
            let escaped = escapeForJS(blocksJson)
            let js = "window.mindmark.receiveFromSwift('loadDocument', {blocksJson: \"\(escaped)\"})"
            webView.evaluateJavaScript(js) { _, error in
                if let error = error { print("[Bridge] Failed to load JSON: \(error)") }
            }
        }

        func loadDocument(markdown: String) {
            guard isEditorReady, let webView = webView else {
                pendingLoad = { [weak self] in self?.loadDocument(markdown: markdown) }
                return
            }
            let escaped = escapeForJS(markdown)
            let js = "window.mindmark.receiveFromSwift('loadDocument', {markdown: \"\(escaped)\"})"
            webView.evaluateJavaScript(js) { _, error in
                if let error = error { print("[Bridge] Failed to load markdown: \(error)") }
            }
        }

        func requestContent() {
            guard isEditorReady, let webView = webView else { return }
            webView.evaluateJavaScript("window.mindmark.receiveFromSwift('getContent', {})", completionHandler: nil)
        }

        // MARK: Navigation Delegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[Editor] WebView loaded")
        }

        // MARK: UI Delegate — File Upload Panel (macOS)

        #if os(macOS)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection

            panel.begin { response in
                if response == .OK {
                    completionHandler(panel.urls)
                } else {
                    completionHandler(nil)
                }
            }
        }
        #endif

        // MARK: Helpers

        private func escapeForJS(_ str: String) -> String {
            str.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: "\"", with: "\\\"")
               .replacingOccurrences(of: "\n", with: "\\n")
               .replacingOccurrences(of: "\r", with: "\\r")
               .replacingOccurrences(of: "\t", with: "\\t")
        }
    }
}
