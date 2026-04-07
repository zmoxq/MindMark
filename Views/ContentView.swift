// ContentView.swift
// Main layout with note management (rename, move, new folder), external edit detection, iOS support

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        if vaultManager.vaultURL != nil {
            MainEditorView()
        } else {
            WelcomeView()
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var showFolderPicker = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.indigo.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 44))
                    .foregroundStyle(.indigo)
            }

            VStack(spacing: 8) {
                Text("MindMark")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Your notes. Your folder. Your way.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("Choose a folder to store your notes as plain Markdown.\nSync with Dropbox, iCloud Drive, Google Drive, or any tool you like.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
                .lineSpacing(3)

            Button(action: openVault) {
                Label("Open Vault Folder", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)

            HStack(spacing: 32) {
                FeatureBadge(icon: "doc.text", text: "Plain .md files")
                FeatureBadge(icon: "arrow.triangle.2.circlepath", text: "Any sync tool")
                FeatureBadge(icon: "lock.open", text: "No lock-in")
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(48)
        #if os(iOS)
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                if let url = url { vaultManager.openVault(at: url) }
            }
        }
        #endif
    }

    private func openVault() {
        #if os(macOS)
        vaultManager.selectVault()
        #else
        showFolderPicker = true
        #endif
    }
}

struct FeatureBadge: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.indigo)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Main Editor Layout

struct MainEditorView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @State private var showNewNoteAlert = false
    @State private var showNewFolderAlert = false
    @State private var newItemName = ""
    @State private var sidebarSelection: Note?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            if vaultManager.selectedNote != nil {
                EditorContainerView()
            } else {
                EmptyEditorView()
            }
        }
        .onChange(of: sidebarSelection) { _, newNote in
            if let note = newNote, !note.isDirectory {
                DispatchQueue.main.async {
                    vaultManager.openNote(note)
                }
            }
        }
        .onChange(of: vaultManager.selectedNote) { _, newNote in
            if sidebarSelection != newNote {
                sidebarSelection = newNote
            }
        }
        .toolbar {
            #if os(macOS)
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button(action: { showNewNoteAlert = true }) {
                        Label("New Note", systemImage: "doc.badge.plus")
                    }
                    Button(action: { showNewFolderAlert = true }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .help("Create new note or folder")

                Button(action: { vaultManager.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh file list")
            }
            #else
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { showNewNoteAlert = true }) {
                        Label("New Note", systemImage: "doc.badge.plus")
                    }
                    Button(action: { showNewFolderAlert = true }) {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
            #endif
        }
        .alert("New Note", isPresented: $showNewNoteAlert) {
            TextField("Note name", text: $newItemName)
            Button("Create") {
                guard !newItemName.isEmpty else { return }
                vaultManager.createNote(name: newItemName)
                newItemName = ""
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        } message: {
            Text("Enter a name for your new note")
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newItemName)
            Button("Create") {
                guard !newItemName.isEmpty else { return }
                vaultManager.createFolder(name: newItemName)
                newItemName = ""
            }
            Button("Cancel", role: .cancel) { newItemName = "" }
        } message: {
            Text("Enter a name for the new folder")
        }
    }
}

// MARK: - Empty Editor

struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.cursor")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(.quaternary)
            Text("Select a note to start editing")
                .font(.title3)
                .foregroundStyle(.tertiary)
            #if os(macOS)
            Text("or press ⌘N to create a new one")
                .font(.callout)
                .foregroundStyle(.quaternary)
            #endif
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Binding var selection: Note?

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                query: $vaultManager.searchQuery,
                onSearch: { vaultManager.performSearch() },
                onClear: { vaultManager.clearSearch() }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if !vaultManager.searchQuery.isEmpty {
                SearchResultsView(selection: $selection)
            } else {
                FileTreeView(selection: $selection)
            }
        }
        #if os(macOS)
        .frame(minWidth: 240, idealWidth: 260)
        #endif
        .navigationTitle("Notes")
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var query: String
    var onSearch: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.body)
            TextField("Search notes...", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit { onSearch() }
                .onChange(of: query) { _, newValue in
                    if newValue.isEmpty { onClear() } else { onSearch() }
                }
            if !query.isEmpty {
                Button(action: { query = ""; onClear() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Search Results

struct SearchResultsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Binding var selection: Note?

    var body: some View {
        if vaultManager.searchResults.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.title2).foregroundStyle(.quaternary)
                Text("No results").font(.callout).foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            List(selection: $selection) {
                ForEach(vaultManager.searchResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.caption).foregroundStyle(.indigo.opacity(0.7))
                            Text(result.note.name)
                                .font(.body).fontWeight(.medium).lineLimit(1)
                        }
                        Text(result.matchLine)
                            .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.vertical, 3)
                    .tag(result.note)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - File Tree

struct FileTreeView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @Binding var selection: Note?

    var body: some View {
        List(selection: $selection) {
            ForEach(vaultManager.notes) { note in
                if note.isDirectory {
                    DisclosureGroup {
                        if let children = note.children {
                            ForEach(children) { child in
                                NoteRow(note: child).tag(child)
                            }
                        }
                    } label: {
                        Label(note.name, systemImage: "folder.fill")
                            .font(.body).foregroundStyle(.secondary)
                    }
                } else {
                    NoteRow(note: note).tag(note)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct NoteRow: View {
    let note: Note
    @EnvironmentObject var vaultManager: VaultManager
    @State private var showRenameAlert = false
    @State private var renameName = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(.indigo.opacity(0.7))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.name).font(.body).lineLimit(1)
                Text(note.modifiedDate, style: .relative)
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                renameName = note.name
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            // Move to submenu
            let dirs = vaultManager.availableDirectories()
            if dirs.count > 1 {
                Menu("Move to...") {
                    ForEach(dirs, id: \.url) { dir in
                        Button(dir.name) {
                            vaultManager.moveNote(note, to: dir.url)
                        }
                    }
                }
            }

            Divider()

            #if os(macOS)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([note.fullPath])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            #endif

            Divider()

            Button(role: .destructive) {
                vaultManager.deleteNote(note)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Rename Note", isPresented: $showRenameAlert) {
            TextField("New name", text: $renameName)
            Button("Rename") {
                guard !renameName.isEmpty, renameName != note.name else { return }
                vaultManager.renameNote(note, to: renameName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for \"\(note.name)\"")
        }
    }
}

// MARK: - Editor Container

struct EditorContainerView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var aiService: AIService
    @State private var editorId = UUID()
    @State private var showAIPanel = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if vaultManager.externalEditDetected {
                    ExternalEditBanner()
                }

                EditorTitleBar(showAIPanel: $showAIPanel)
                Divider()

                EditorWebView(
                    markdown: $vaultManager.currentMarkdown,
                    blocksJson: $vaultManager.currentBlocksJson,
                    onContentChanged: { markdown, blocksJson in
                        vaultManager.contentDidChange(markdown: markdown, blocksJson: blocksJson)
                    },
                    vaultManager: vaultManager
                )
                .id(editorId)
            }

            // AI Panel overlay
            if showAIPanel {
                AIPanelView(aiService: aiService, isPresented: $showAIPanel)
                    .padding(20)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: showAIPanel)
        .onChange(of: vaultManager.selectedNote) { _, _ in
            editorId = UUID()
        }
        .onChange(of: vaultManager.externalEditDetected) { _, detected in
            if detected { editorId = UUID() }
        }
        #if os(macOS)
        .onDisappear { vaultManager.saveCurrentNote() }
        #endif
    }
}

/// Banner shown when a file was modified externally
struct ExternalEditBanner: View {
    @EnvironmentObject var vaultManager: VaultManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This file was modified externally. Content has been reloaded.")
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                vaultManager.dismissExternalEdit()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}

struct EditorTitleBar: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var aiService: AIService
    @Binding var showAIPanel: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Text(vaultManager.selectedNote?.name ?? "")
                .font(.callout)
                .fontWeight(.medium)

            if let note = vaultManager.selectedNote, note.id.contains("/") {
                Text("in \(parentPath(note.id))")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            // AI button
            Button(action: { showAIPanel.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("AI")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(showAIPanel ? Color.indigo.opacity(0.15) : Color.gray.opacity(0.1), in: Capsule())
//                .background(showAIPanel ? .indigo.opacity(0.15) : .fill.tertiary, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showAIPanel ? .indigo : .secondary)
            .help("AI Assistant")
            .disabled(!aiService.hasAPIKey)

            // Save status
            Group {
                if vaultManager.isDirty {
                    HStack(spacing: 4) {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                        Text("Editing").font(.caption2).foregroundStyle(.orange)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green.opacity(0.6))
                        Text("Saved").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vaultManager.isDirty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func parentPath(_ path: String) -> String {
        path.components(separatedBy: "/").dropLast().joined(separator: "/")
    }
}

// MARK: - iOS Folder Picker

#if os(iOS)
import UIKit

struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { onPick(nil) }
    }
}
#endif
