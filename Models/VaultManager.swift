// VaultManager.swift
// Dual-format storage: .md + .md.json | Per-note attachments | File watching | Note management

import SwiftUI
import Combine

// MARK: - Note Model

struct Note: Identifiable, Hashable {
    let id: String
    let name: String
    let fullPath: URL
    let isDirectory: Bool
    let children: [Note]?
    var modifiedDate: Date

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }

    var jsonPath: URL {
        let dir = fullPath.deletingLastPathComponent()
        return dir.appendingPathComponent(".\(fullPath.lastPathComponent).json")
    }

    var attachmentFolder: URL {
        let dir = fullPath.deletingLastPathComponent()
        return dir.appendingPathComponent(name)
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id = UUID()
    let note: Note
    let matchLine: String
    let lineNumber: Int
}

// MARK: - VaultManager

@MainActor
class VaultManager: ObservableObject {
    @Published var vaultURL: URL? { didSet { saveVaultBookmark() } }
    @Published var notes: [Note] = []
    @Published var selectedNote: Note?
    @Published var currentMarkdown: String = ""
    @Published var currentBlocksJson: String = ""
    @Published var isDirty: Bool = false
    @Published var externalEditDetected: Bool = false

    // Search
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false

    // Theme
    @Published var currentTheme: String = "default" {
        didSet { UserDefaults.standard.set(currentTheme, forKey: "selectedTheme") }
    }
    @Published var availableThemes: [ThemeInfo] = []

    // Favorites
    @Published var favoriteNoteIds: Set<String> = []

    // Auto-save
    private let autoSaveInterval: TimeInterval = 2.0
    private var autoSaveWork: DispatchWorkItem?

    // File watching
    private var fileWatchTimer: Timer?
    private var lastKnownModDates: [String: Date] = [:]

    init() {
        currentTheme = UserDefaults.standard.string(forKey: "selectedTheme") ?? "default"
        favoriteNoteIds = Set(UserDefaults.standard.stringArray(forKey: "favoriteNotes") ?? [])
        restoreVaultBookmark()
        if let url = vaultURL {
            loadNotes(from: url)
            loadThemes()
            startFileWatching()
        }
    }

    deinit {
        fileWatchTimer?.invalidate()
    }

    // MARK: - Auto Save

    func contentDidChange(markdown: String, blocksJson: String) {
        currentMarkdown = markdown
        currentBlocksJson = blocksJson
        isDirty = true
        scheduleAutoSave()
    }

    private func scheduleAutoSave() {
        autoSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.saveCurrentNote()
            }
        }
        autoSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoSaveInterval, execute: work)
    }

    // MARK: - File Watching (External Edit Detection)

    func startFileWatching() {
        fileWatchTimer?.invalidate()
        fileWatchTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForExternalChanges()
            }
        }
    }

    private func checkForExternalChanges() {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default

        // Check if the currently open note was modified externally
        if let note = selectedNote, !isDirty {
            let mdDate = (try? fm.attributesOfItem(atPath: note.fullPath.path)[.modificationDate] as? Date) ?? .distantPast
            if let lastKnown = lastKnownModDates[note.id], mdDate > lastKnown {
                print("[Vault] External edit detected: \(note.name)")
                externalEditDetected = true
                // Reload the note content
                let content = loadNoteContent(note)
                currentMarkdown = content.markdown ?? ""
                currentBlocksJson = content.blocksJson ?? ""
                lastKnownModDates[note.id] = mdDate
            }
        }

        // Check if file list changed (new/deleted files)
        let currentAllNotes = allNotes()
        let currentIds = Set(currentAllNotes.map { $0.id })
        let knownIds = Set(lastKnownModDates.keys)

        if currentIds != knownIds {
            loadNotes(from: vault)
            updateModDateCache()
        }
    }

    private func updateModDateCache() {
        let fm = FileManager.default
        lastKnownModDates.removeAll()
        for note in allNotes() {
            let date = (try? fm.attributesOfItem(atPath: note.fullPath.path)[.modificationDate] as? Date) ?? Date()
            lastKnownModDates[note.id] = date
        }
    }

    /// Reload the currently open note (after external edit)
    func reloadCurrentNote() {
        guard let note = selectedNote else { return }
        let content = loadNoteContent(note)
        currentMarkdown = content.markdown ?? ""
        currentBlocksJson = content.blocksJson ?? ""
        isDirty = false
        externalEditDetected = false
    }

    func dismissExternalEdit() {
        externalEditDetected = false
    }

    // MARK: - Vault Selection

    func selectVault() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Choose Your Vault Folder"
        panel.message = "Select a folder for your notes. Put it in Dropbox, iCloud Drive, or anywhere."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            openVault(at: url)
        }
        #endif
    }

    func openVault(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("[Vault] Failed to access security-scoped resource")
            return
        }
        vaultURL = url
        loadNotes(from: url)
        updateModDateCache()
        startFileWatching()
    }

    // MARK: - File Tree

    func loadNotes(from url: URL) {
        notes = buildFileTree(at: url, vaultRoot: url)
    }

    private func buildFileTree(at directory: URL, vaultRoot: URL) -> [Note] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let mdNames = Set(contents
            .filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
        )

        var items: [Note] = []

        for fileURL in contents {
            let relativePath = fileURL.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            if relativePath.hasPrefix(".") { continue }

            let res = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDir = res?.isDirectory ?? false
            let modDate = res?.contentModificationDate ?? Date()

            if isDir {
                if mdNames.contains(fileURL.lastPathComponent) { continue }
                if fileURL.lastPathComponent == "attachments" && directory == vaultRoot { continue }

                let children = buildFileTree(at: fileURL, vaultRoot: vaultRoot)
                // Show all folders, even empty ones (user may want to add notes later)
                items.append(Note(
                    id: relativePath, name: fileURL.lastPathComponent,
                    fullPath: fileURL, isDirectory: true,
                    children: children.isEmpty ? nil : children, modifiedDate: modDate
                ))
            } else if fileURL.pathExtension == "md" {
                items.append(Note(
                    id: relativePath,
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    fullPath: fileURL, isDirectory: false,
                    children: nil, modifiedDate: modDate
                ))
            }
        }

        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Note Content Loading

    struct NoteContent {
        let markdown: String?
        let blocksJson: String?
    }

    func loadNoteContent(_ note: Note) -> NoteContent {
        let fm = FileManager.default
        let mdExists = fm.fileExists(atPath: note.fullPath.path)
        let jsonExists = fm.fileExists(atPath: note.jsonPath.path)

        if jsonExists && mdExists {
            let mdDate = (try? fm.attributesOfItem(atPath: note.fullPath.path)[.modificationDate] as? Date) ?? .distantPast
            let jsonDate = (try? fm.attributesOfItem(atPath: note.jsonPath.path)[.modificationDate] as? Date) ?? .distantPast

            if mdDate > jsonDate {
                print("[Vault] External edit detected — loading from Markdown")
                return NoteContent(markdown: try? String(contentsOf: note.fullPath, encoding: .utf8), blocksJson: nil)
            } else {
                return NoteContent(markdown: nil, blocksJson: try? String(contentsOf: note.jsonPath, encoding: .utf8))
            }
        } else if jsonExists {
            return NoteContent(markdown: nil, blocksJson: try? String(contentsOf: note.jsonPath, encoding: .utf8))
        } else if mdExists {
            return NoteContent(markdown: try? String(contentsOf: note.fullPath, encoding: .utf8), blocksJson: nil)
        }
        return NoteContent(markdown: nil, blocksJson: nil)
    }

    // MARK: - Note Operations

    func openNote(_ note: Note) {
        if isDirty, selectedNote != nil { saveCurrentNote() }
        autoSaveWork?.cancel()

        selectedNote = note
        let content = loadNoteContent(note)
        currentMarkdown = content.markdown ?? ""
        currentBlocksJson = content.blocksJson ?? ""
        isDirty = false
        externalEditDetected = false

        // Update mod date cache
        let fm = FileManager.default
        lastKnownModDates[note.id] = (try? fm.attributesOfItem(atPath: note.fullPath.path)[.modificationDate] as? Date) ?? Date()
    }

    func saveCurrentNote() {
        guard let note = selectedNote, isDirty else { return }
        saveDualFormat(note: note, markdown: currentMarkdown, blocksJson: currentBlocksJson)
        isDirty = false
        // Update cache so file watcher doesn't trigger
        lastKnownModDates[note.id] = Date()
    }

    func saveDualFormat(note: Note, markdown: String, blocksJson: String) {
        do {
            try markdown.write(to: note.fullPath, atomically: true, encoding: .utf8)
        } catch {
            print("[Vault] Failed to save .md: \(error)")
        }

        if !blocksJson.isEmpty {
            do {
                try blocksJson.write(to: note.jsonPath, atomically: true, encoding: .utf8)
            } catch {
                print("[Vault] Failed to save .json: \(error)")
            }
        }
        print("[Vault] Saved: \(note.name)")
    }

    func createNote(name: String, template: NoteTemplate = .default, in directory: URL? = nil) {
        guard let vault = vaultURL else { return }
        let parentDir = directory ?? vault
        let sanitized = name.replacingOccurrences(of: "/", with: "-")
        let fileName = sanitized.hasSuffix(".md") ? sanitized : "\(sanitized).md"
        let fileURL = parentDir.appendingPathComponent(fileName)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let content = template.initialContent(title: name)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            loadNotes(from: vault)
            updateModDateCache()
            let relPath = fileURL.path.replacingOccurrences(of: vault.path + "/", with: "")
            if let newNote = findNote(byId: relPath, in: notes) {
                openNote(newNote)
            }
        } catch {
            print("[Vault] Failed to create: \(error)")
        }
    }

    /// Create a new subfolder
    func createFolder(name: String, in directory: URL? = nil) {
        guard let vault = vaultURL else { return }
        let parentDir = directory ?? vault
        let folderURL = parentDir.appendingPathComponent(name)

        guard !FileManager.default.fileExists(atPath: folderURL.path) else { return }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            loadNotes(from: vault)
            updateModDateCache()
        } catch {
            print("[Vault] Failed to create folder: \(error)")
        }
    }

    /// Rename a note (updates .md, .md.json, and attachment folder)
    func renameNote(_ note: Note, to newName: String) {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default
        let dir = note.fullPath.deletingLastPathComponent()
        let newMdURL = dir.appendingPathComponent("\(newName).md")

        guard !fm.fileExists(atPath: newMdURL.path) else {
            print("[Vault] A note named '\(newName)' already exists")
            return
        }

        do {
            // Rename .md
            try fm.moveItem(at: note.fullPath, to: newMdURL)

            // Rename .md.json
            let newJsonURL = dir.appendingPathComponent(".\(newName).md.json")
            if fm.fileExists(atPath: note.jsonPath.path) {
                try fm.moveItem(at: note.jsonPath, to: newJsonURL)
            }

            // Rename attachment folder
            let newAttachFolder = dir.appendingPathComponent(newName)
            if fm.fileExists(atPath: note.attachmentFolder.path) {
                try fm.moveItem(at: note.attachmentFolder, to: newAttachFolder)
            }

            // Reload
            loadNotes(from: vault)
            updateModDateCache()

            // Re-select renamed note
            let relPath = newMdURL.path.replacingOccurrences(of: vault.path + "/", with: "")
            if let renamed = findNote(byId: relPath, in: notes) {
                openNote(renamed)
            }

            print("[Vault] Renamed: \(note.name) → \(newName)")
        } catch {
            print("[Vault] Failed to rename: \(error)")
        }
    }

    /// Move a note to a different directory
    func moveNote(_ note: Note, to targetDir: URL) {
        guard let vault = vaultURL else { return }
        let fm = FileManager.default
        let newMdURL = targetDir.appendingPathComponent(note.fullPath.lastPathComponent)

        guard !fm.fileExists(atPath: newMdURL.path) else { return }

        do {
            try fm.moveItem(at: note.fullPath, to: newMdURL)

            // Move .md.json
            let newJsonName = ".\(note.fullPath.lastPathComponent).json"
            let newJsonURL = targetDir.appendingPathComponent(newJsonName)
            if fm.fileExists(atPath: note.jsonPath.path) {
                try fm.moveItem(at: note.jsonPath, to: newJsonURL)
            }

            // Move attachment folder
            let newAttachFolder = targetDir.appendingPathComponent(note.name)
            if fm.fileExists(atPath: note.attachmentFolder.path) {
                try fm.moveItem(at: note.attachmentFolder, to: newAttachFolder)
            }

            loadNotes(from: vault)
            updateModDateCache()

            let relPath = newMdURL.path.replacingOccurrences(of: vault.path + "/", with: "")
            if let moved = findNote(byId: relPath, in: notes) {
                openNote(moved)
            }
        } catch {
            print("[Vault] Failed to move: \(error)")
        }
    }

    func deleteNote(_ note: Note) {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: note.fullPath)
            if fm.fileExists(atPath: note.jsonPath.path) { try fm.removeItem(at: note.jsonPath) }
            if fm.fileExists(atPath: note.attachmentFolder.path) { try fm.removeItem(at: note.attachmentFolder) }

            if selectedNote == note {
                selectedNote = nil
                currentMarkdown = ""
                currentBlocksJson = ""
                isDirty = false
            }
            if let vault = vaultURL {
                loadNotes(from: vault)
                updateModDateCache()
            }
        } catch {
            print("[Vault] Failed to delete: \(error)")
        }
    }

    func refresh() {
        if let url = vaultURL {
            loadNotes(from: url)
            updateModDateCache()
        }
    }

    // MARK: - Attachment Management

    func ensureAttachmentFolder(for note: Note) -> URL {
        let folder = note.attachmentFolder
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Result of saving an attachment
    struct AttachmentResult {
        let absoluteURL: String   // file:// URL for WKWebView display
        let relativePath: String  // ./note-name/file.png for markdown storage
    }

    func saveAttachment(for note: Note, data: Data, fileName: String) -> AttachmentResult? {
        let folder = ensureAttachmentFolder(for: note)
        let fileURL = folder.appendingPathComponent(fileName)

        var finalURL = fileURL
        var counter = 1
        while FileManager.default.fileExists(atPath: finalURL.path) {
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension
            finalURL = folder.appendingPathComponent("\(name)-\(counter).\(ext)")
            counter += 1
        }

        do {
            try data.write(to: finalURL)
            let relativePath = "./\(note.name)/\(finalURL.lastPathComponent)"
            let absoluteURL = finalURL.absoluteString  // file:///Users/.../note-name/image.png
            print("[Vault] Attachment saved: \(relativePath) → \(absoluteURL)")
            return AttachmentResult(absoluteURL: absoluteURL, relativePath: relativePath)
        } catch {
            print("[Vault] Failed to save attachment: \(error)")
            return nil
        }
    }

    // MARK: - Search

    func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []; isSearching = false; return
        }
        isSearching = true
        let query = searchQuery.lowercased()
        var results: [SearchResult] = []
        searchNotes(notes, query: query, results: &results)
        searchResults = results
        isSearching = false
    }

    private func searchNotes(_ notes: [Note], query: String, results: inout [SearchResult]) {
        for note in notes {
            if note.isDirectory {
                if let children = note.children { searchNotes(children, query: query, results: &results) }
                continue
            }
            if note.name.lowercased().contains(query) {
                results.append(SearchResult(note: note, matchLine: "File name match", lineNumber: 0))
                continue
            }
            guard let content = try? String(contentsOf: note.fullPath, encoding: .utf8) else { continue }
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                if line.lowercased().contains(query) {
                    results.append(SearchResult(note: note, matchLine: String(line.trimmingCharacters(in: .whitespaces).prefix(120)), lineNumber: index + 1))
                    break
                }
            }
        }
    }

    func clearSearch() { searchQuery = ""; searchResults = []; isSearching = false }

    // MARK: - Favorites

    func isFavorite(_ note: Note) -> Bool {
        favoriteNoteIds.contains(note.id)
    }

    func toggleFavorite(_ note: Note) {
        if favoriteNoteIds.contains(note.id) {
            favoriteNoteIds.remove(note.id)
        } else {
            favoriteNoteIds.insert(note.id)
        }
        saveFavorites()
    }

    func favoriteNotes() -> [Note] {
        let all = allNotes()
        return all.filter { favoriteNoteIds.contains($0.id) }
    }

    /// Recently modified notes (top 8)
    func recentNotes() -> [Note] {
        let all = allNotes()
        return Array(all.sorted { $0.modifiedDate > $1.modifiedDate }.prefix(8))
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteNoteIds), forKey: "favoriteNotes")
    }

    // MARK: - Helpers

    func allNotes() -> [Note] {
        var result: [Note] = []
        collectNotes(from: notes, into: &result)
        return result
    }

    private func collectNotes(from notes: [Note], into result: inout [Note]) {
        for note in notes {
            if note.isDirectory {
                if let children = note.children { collectNotes(from: children, into: &result) }
            } else { result.append(note) }
        }
    }

    private func findNote(byId id: String, in notes: [Note]) -> Note? {
        for note in notes {
            if note.id == id { return note }
            if let children = note.children, let found = findNote(byId: id, in: children) { return found }
        }
        return nil
    }

    /// Get list of directories for "Move to" menu
    func availableDirectories() -> [(name: String, url: URL)] {
        guard let vault = vaultURL else { return [] }
        var dirs: [(String, URL)] = [("Root", vault)]
        collectDirectories(from: notes, into: &dirs)
        return dirs
    }

    private func collectDirectories(from notes: [Note], into result: inout [(String, URL)]) {
        for note in notes where note.isDirectory {
            result.append((note.name, note.fullPath))
            if let children = note.children { collectDirectories(from: children, into: &result) }
        }
    }

    // MARK: - Theme Management

    struct ThemeInfo: Identifiable, Hashable {
        let id: String        // "default", "duying", "minimal-dark", or filename
        let name: String      // Display name
        let isBuiltIn: Bool
        let cssPath: URL?     // nil for default theme
    }

    /// Custom themes directory: ~/Library/Application Support/MindMark/Themes/
    static var customThemesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MindMark/Themes")
    }

    /// Load available themes (built-in from Resources + custom from Application Support)
    func loadThemes() {
        var themes: [ThemeInfo] = []

        // Default (no custom CSS)
        themes.append(ThemeInfo(id: "default", name: "Default", isBuiltIn: true, cssPath: nil))

        // Built-in themes from app bundle
        let builtInThemes = [
            ("duying", "DuYing (读营)"),
            ("minimal-dark", "Minimal Dark"),
            ("academic", "Academic")
        ]

        for (fileName, displayName) in builtInThemes {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "css") {
                themes.append(ThemeInfo(id: fileName, name: displayName, isBuiltIn: true, cssPath: url))
            }
        }

        // Custom themes from ~/Library/Application Support/MindMark/Themes/
        let customDir = Self.customThemesDirectory
        let fm = FileManager.default

        // Create directory if it doesn't exist
        if !fm.fileExists(atPath: customDir.path) {
            try? fm.createDirectory(at: customDir, withIntermediateDirectories: true)
        }

        if let files = try? fm.contentsOfDirectory(at: customDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for file in files where file.pathExtension == "css" {
                let name = file.deletingPathExtension().lastPathComponent
                let displayName = name.replacingOccurrences(of: "-", with: " ").capitalized
                themes.append(ThemeInfo(id: "custom-\(name)", name: displayName, isBuiltIn: false, cssPath: file))
            }
        }

        availableThemes = themes
    }

    /// Get the CSS content for a theme
    func themeCSS(for themeId: String) -> String? {
        guard let theme = availableThemes.first(where: { $0.id == themeId }),
              let cssPath = theme.cssPath else {
            return nil  // default theme = no custom CSS
        }
        return try? String(contentsOf: cssPath, encoding: .utf8)
    }

    // MARK: - Bookmark Persistence

    private func saveVaultBookmark() {
        guard let url = vaultURL else {
            UserDefaults.standard.removeObject(forKey: "vaultBookmark"); return
        }
        do {
            #if os(macOS)
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            #else
            let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            #endif
            UserDefaults.standard.set(data, forKey: "vaultBookmark")
        } catch { print("[Vault] Bookmark save failed: \(error)") }
    }

    private func restoreVaultBookmark() {
        guard let data = UserDefaults.standard.data(forKey: "vaultBookmark") else { return }
        do {
            var isStale = false
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            #else
            let url = try URL(resolvingBookmarkData: data, relativeTo: nil, bookmarkDataIsStale: &isStale)
            #endif
            guard !isStale, url.startAccessingSecurityScopedResource() else { return }
            vaultURL = url
        } catch { print("[Vault] Bookmark restore failed: \(error)") }
    }
}
