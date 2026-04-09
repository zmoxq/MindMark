// EditorWebView.swift
// WKWebView hosting BlockNote — dual format bridge + image upload/download/resolve + file dialog + theme

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
    var themeCSS: String?

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

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let newCSS = themeCSS ?? ""
        if context.coordinator.lastAppliedThemeCSS != newCSS {
            context.coordinator.applyTheme(css: newCSS)
            context.coordinator.lastAppliedThemeCSS = newCSS
        }
    }
}
#endif

// MARK: - iOS

#if os(iOS)
struct EditorWebView: UIViewRepresentable {
    @Binding var markdown: String
    @Binding var blocksJson: String
    var onContentChanged: (String, String) -> Void
    var vaultManager: VaultManager
    var themeCSS: String?

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

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let newCSS = themeCSS ?? ""
        if context.coordinator.lastAppliedThemeCSS != newCSS {
            context.coordinator.applyTheme(css: newCSS)
            context.coordinator.lastAppliedThemeCSS = newCSS
        }
    }
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
            var accessURL = editorURL.deletingLastPathComponent()
            if let vault = vaultURL {
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
        var lastAppliedThemeCSS: String = ""
        private var pendingThemeCSS: String?

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
                // Apply pending theme after editor is ready
                if let css = pendingThemeCSS {
                    applyTheme(css: css)
                    pendingThemeCSS = nil
                } else if !lastAppliedThemeCSS.isEmpty {
                    applyTheme(css: lastAppliedThemeCSS)
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

            case "downloadImage":
                handleImageDownload(payload)

            case "resolveImage":
                handleImageResolve(payload)

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

        // MARK: Image Upload (local file → base64 → save to attachment folder)

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

            let mimeType = mimeTypeForExtension((fileName as NSString).pathExtension.lowercased())

            Task { @MainActor in
                guard let note = vaultManager.selectedNote else {
                    sendImageUploadResult(requestId: requestId, relativePath: nil, error: "No note selected")
                    return
                }

                if let result = vaultManager.saveAttachment(for: note, data: data, fileName: fileName) {
                    // Return base64 data URL for immediate display in WKWebView
                    // (file:// URLs are blocked by sandbox)
                    let dataURL = "data:\(mimeType);base64,\(base64Data)"
                    sendImageUploadResult(requestId: requestId, relativePath: dataURL, error: nil)
                    print("[Bridge] Image uploaded and displayed via data URL, saved at: \(result.relativePath)")
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

        // MARK: Image Download (http URL → URLSession download → save → return relative path)

        private func handleImageDownload(_ payload: [String: Any]?) {
            guard let requestId = payload?["requestId"] as? String,
                  let urlString = payload?["url"] as? String,
                  let url = URL(string: urlString) else {
                print("[Bridge] Invalid downloadImage payload")
                return
            }

            print("[Bridge] Downloading remote image: \(urlString.prefix(80))...")

            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)

                    // Determine file extension from response or URL
                    let httpResponse = response as? HTTPURLResponse
                    let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") ?? ""
                    let ext = extensionForMimeType(contentType) ?? extensionFromURL(url) ?? "jpg"
                    let fileName = "downloaded-\(Int(Date().timeIntervalSince1970)).\(ext)"

                    await MainActor.run {
                        guard let note = self.vaultManager.selectedNote else {
                            self.sendImageDownloadResult(requestId: requestId, relativePath: nil, error: "No note selected")
                            return
                        }

                        if let result = self.vaultManager.saveAttachment(for: note, data: data, fileName: fileName) {
                            print("[Bridge] Remote image saved: \(result.relativePath)")
                            self.sendImageDownloadResult(requestId: requestId, relativePath: result.relativePath, error: nil)
                        } else {
                            self.sendImageDownloadResult(requestId: requestId, relativePath: nil, error: "Failed to save downloaded image")
                        }
                    }
                } catch {
                    print("[Bridge] Image download failed: \(error)")
                    await MainActor.run {
                        self.sendImageDownloadResult(requestId: requestId, relativePath: nil, error: "Download failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        private func sendImageDownloadResult(requestId: String, relativePath: String?, error: String?) {
            guard let webView = webView else { return }

            let pathStr = relativePath.map { "\"\(escapeForJS($0))\"" } ?? "null"
            let errorStr = error.map { "\"\(escapeForJS($0))\"" } ?? "null"

            let js = """
            window.mindmark.receiveFromSwift('imageDownloaded', {
                requestId: "\(escapeForJS(requestId))",
                relativePath: \(pathStr),
                error: \(errorStr)
            })
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { _, err in
                    if let err = err {
                        print("[Bridge] Failed to send imageDownloaded: \(err)")
                    }
                }
            }
        }

        // MARK: Image Resolve (relative path → read file → return data URL)

        private func handleImageResolve(_ payload: [String: Any]?) {
            guard let requestId = payload?["requestId"] as? String,
                  let relativePath = payload?["url"] as? String else {
                print("[Bridge] Invalid resolveImage payload")
                return
            }

            print("[Bridge] Resolving image: \(relativePath)")

            Task { @MainActor in
                guard let note = vaultManager.selectedNote,
                      let vaultURL = vaultManager.vaultURL else {
                    sendImageResolveResult(requestId: requestId, dataURL: nil)
                    return
                }

                // Resolve the relative path against the note's parent directory
                let noteDir = note.fullPath.deletingLastPathComponent()
                let imageURL: URL

                if relativePath.hasPrefix("./") {
                    // Relative to note's directory: "./notename/image.png"
                    let cleanPath = String(relativePath.dropFirst(2)) // remove "./"
                    imageURL = noteDir.appendingPathComponent(cleanPath)
                } else {
                    // Try as relative to vault root
                    imageURL = vaultURL.appendingPathComponent(relativePath)
                }

                guard FileManager.default.fileExists(atPath: imageURL.path) else {
                    print("[Bridge] Image file not found: \(imageURL.path)")
                    sendImageResolveResult(requestId: requestId, dataURL: nil)
                    return
                }

                do {
                    let data = try Data(contentsOf: imageURL)
                    let ext = imageURL.pathExtension.lowercased()
                    let mimeType = mimeTypeForExtension(ext)
                    let base64 = data.base64EncodedString()
                    let dataURL = "data:\(mimeType);base64,\(base64)"
                    print("[Bridge] Image resolved: \(relativePath) → \(data.count / 1024)KB data URL")
                    sendImageResolveResult(requestId: requestId, dataURL: dataURL)
                } catch {
                    print("[Bridge] Failed to read image file: \(error)")
                    sendImageResolveResult(requestId: requestId, dataURL: nil)
                }
            }
        }

        private func sendImageResolveResult(requestId: String, dataURL: String?) {
            guard let webView = webView else { return }

            let dataURLStr = dataURL.map { "\"\(escapeForJS($0))\"" } ?? "null"

            let js = """
            window.mindmark.receiveFromSwift('imageResolved', {
                requestId: "\(escapeForJS(requestId))",
                dataURL: \(dataURLStr)
            })
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { _, err in
                    if let err = err {
                        print("[Bridge] Failed to send imageResolved: \(err)")
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

        func applyTheme(css: String) {
            guard isEditorReady, let webView = webView else {
                pendingThemeCSS = css
                return
            }
            let escaped = escapeForJS(css)
            let js = "window.mindmark.receiveFromSwift('applyTheme', {css: \"\(escaped)\"})"
            webView.evaluateJavaScript(js) { _, error in
                if let error = error { print("[Bridge] Failed to apply theme: \(error)") }
                else { print("[Bridge] Theme applied (\(css.count) bytes)") }
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

        private func mimeTypeForExtension(_ ext: String) -> String {
            switch ext {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "svg": return "image/svg+xml"
            case "webp": return "image/webp"
            case "tiff", "tif": return "image/tiff"
            case "bmp": return "image/bmp"
            case "ico": return "image/x-icon"
            default: return "image/png"
            }
        }

        private func extensionForMimeType(_ mimeType: String) -> String? {
            let map: [String: String] = [
                "image/png": "png",
                "image/jpeg": "jpg",
                "image/gif": "gif",
                "image/webp": "webp",
                "image/svg+xml": "svg",
                "image/tiff": "tiff",
                "image/bmp": "bmp",
                "image/x-icon": "ico",
            ]
            let cleaned = mimeType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? mimeType
            return map[cleaned]
        }

        private func extensionFromURL(_ url: URL) -> String? {
            let ext = url.pathExtension.lowercased()
            let valid = ["png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "bmp", "ico"]
            return valid.contains(ext) ? ext : nil
        }
    }
}
