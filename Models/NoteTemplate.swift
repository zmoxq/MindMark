// NoteTemplate.swift
// Note type system — defines available templates and their initial content

import SwiftUI

// MARK: - NoteTemplate

enum NoteTemplate: String, CaseIterable, Identifiable {
    case `default` = "default"
    case travel    = "travel"
    // Future: case stock = "stock"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Note"
        case .travel:  return "Travel"
        }
    }

    var description: String {
        switch self {
        case .default: return "A blank note for anything"
        case .travel:  return "Trip research, itinerary & journal"
        }
    }

    var icon: String {
        switch self {
        case .default: return "doc.text"
        case .travel:  return "airplane"
        }
    }

    var accentColor: Color {
        switch self {
        case .default: return .indigo
        case .travel:  return .orange
        }
    }

    // MARK: - Initial Markdown Content

    func initialContent(title: String) -> String {
        switch self {
        case .default:
            return defaultContent(title: title)
        case .travel:
            return travelContent(title: title)
        }
    }

    // MARK: - Default Template

    private func defaultContent(title: String) -> String {
        let today = Self.todayString()
        return """
        ---
        title: \(title)
        type: default
        created: \(today)
        tags: []
        ---

        # \(title)

        """
    }

    // MARK: - Travel Template

    private func travelContent(title: String) -> String {
        let today = Self.todayString()
        return """
        ---
        title: \(title)
        type: travel
        destination:
        depart:
        return:
        travelers: 1
        status: planning
        created: \(today)
        tags: [travel]
        ---

        # \(title)

        ## 📚 深度了解

        > 出发前在这里积累背景知识——历史、文化、实用信息。旅途中你会真正"看懂"眼前的一切。

        ### 历史与文化

        ### 必知实用信息

        - **签证**：
        - **货币**：
        - **语言**：
        - **时差**：
        - **最佳旅行时间**：

        ### 交通概览

        ---

        ## 🗺️ 行程规划

        > 先填城市和日期，再往里填景点和待办。

        ### 城市 / 地区 · Day X–X

        #### Day 1

        **📚 Research**

        *(在这里记录你搜集到的背景信息、攻略细节)*

        **✅ 当天待办**

        - [ ] 
        - [ ] 
        - [ ] 

        **🍽️ 餐厅**

        | 名称 | 菜系 | 价位 | 备注 |
        |------|------|------|------|
        |      |      |      |      |

        ---

        ## 📖 旅行故事

        > 旅途中随手记录感受，回来后整理成属于自己的记忆。

        ### Day 1 · 

        *(在这里写下当天的感受，插入照片)*

        """
    }

    // MARK: - Helpers

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Note Type Detection

extension Note {
    /// Parse the `type` field from frontmatter without loading full content
    var noteType: NoteTemplate {
        guard !isDirectory,
              let content = try? String(contentsOf: fullPath, encoding: .utf8) else {
            return .default
        }
        return NoteTemplate(rawValue: parseFrontmatterType(content)) ?? .default
    }

    private func parseFrontmatterType(_ content: String) -> String {
        // Quick parse: look for `type: xxx` within the first frontmatter block
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return "default" }
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            let parts = line.components(separatedBy: ":")
            if parts.first?.trimmingCharacters(in: .whitespaces) == "type" {
                return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        return "default"
    }
}
