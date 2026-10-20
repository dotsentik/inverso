import XCTest

/// Static checks of the logging rules in Log.swift, run over the app sources:
/// no NSLog/print, and user text only at `.debug` with `privacy: .private`.
final class LoggingPolicyTests: XCTestCase {

    /// Variable names that hold typed, selected or converted user text.
    private static let userTextNames = [
        "text", "selectedText", "convertedText", "inputText", "outputText",
        "lineText", "token", "keep", "convert", "trimmed", "converted", "result", "info.text",
    ]

    private static let aboveDebug = ["info", "notice", "warning", "error", "fault", "critical", "log"]

    private struct SourceLine {
        let file: String
        let number: Int
        let text: String
    }

    private func sourceLines() throws -> [SourceLine] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Inverso")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var lines: [SourceLine] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let content = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            var index = 0
            while index < content.count {
                // A logger call wrapped over several lines is checked as one line
                var text = content[index]
                let start = index
                if text.contains("Log.") {
                    var depth = parenthesisDepth(text)
                    while depth > 0 && index + 1 < content.count {
                        index += 1
                        text += " " + content[index].trimmingCharacters(in: .whitespaces)
                        depth += parenthesisDepth(content[index])
                    }
                }
                lines.append(SourceLine(file: url.lastPathComponent, number: start + 1, text: text))
                index += 1
            }
        }
        XCTAssertFalse(lines.isEmpty, "No sources found at \(sources.path)")
        return lines
    }

    private func parenthesisDepth(_ line: String) -> Int {
        line.reduce(0) { depth, char in depth + (char == "(" ? 1 : char == ")" ? -1 : 0) }
    }

    private func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    func testNoNSLogOrPrint() throws {
        for line in try sourceLines() where !isComment(line.text) {
            XCTAssertFalse(line.text.contains("NSLog("), "\(line.file):\(line.number) uses NSLog")
            XCTAssertNil(
                line.text.range(of: #"(^|[^.\w])print\("#, options: .regularExpression),
                "\(line.file):\(line.number) uses print")
        }
    }

    func testNoUserTextAboveDebug() throws {
        let levels = Self.aboveDebug.joined(separator: "|")
        for line in try sourceLines() where !isComment(line.text) {
            guard line.text.range(of: #"Log\.\w+\.(\#(levels))\("#, options: .regularExpression) != nil else {
                continue
            }
            XCTAssertFalse(
                line.text.contains(".private"),
                "\(line.file):\(line.number) logs private data above .debug")
            for name in Self.userTextNames {
                XCTAssertFalse(
                    line.text.contains("\\(\(name)"),
                    "\(line.file):\(line.number) logs '\(name)' above .debug")
            }
        }
    }

    func testUserTextAtDebugIsPrivate() throws {
        for line in try sourceLines()
        where !isComment(line.text) && line.text.contains("Log.") && line.text.contains(".debug(") {
            for name in Self.userTextNames {
                let pattern = #"\\\("# + NSRegularExpression.escapedPattern(for: name) + #"(\)| \?\?[^,)]*\))"#
                XCTAssertNil(
                    line.text.range(of: pattern, options: .regularExpression),
                    "\(line.file):\(line.number) logs '\(name)' without privacy: .private")
            }
        }
    }
}
