import Foundation

package struct MathSpan: Equatable, Sendable {
    package var range: NSRange
    package var latex: String
    package var display: Bool
    package var markerLength: Int { display ? 2 : 1 }
    package var openRange: NSRange { NSRange(location: range.location, length: markerLength) }
    package var closeRange: NSRange { NSRange(location: NSMaxRange(range) - markerLength, length: markerLength) }
    package var innerRange: NSRange {
        NSRange(location: range.location + markerLength, length: max(0, range.length - 2 * markerLength))
    }
}

package struct CodeSpan: Equatable, Sendable {
    package var range: NSRange
    package var innerRange: NSRange
    package var openRange: NSRange { NSRange(location: range.location, length: innerRange.location - range.location) }
    package var closeRange: NSRange { NSRange(location: NSMaxRange(innerRange), length: NSMaxRange(range) - NSMaxRange(innerRange)) }
}

package struct CodeBlock: Equatable, Sendable {
    package var range: NSRange
    package var language: String
    package var openRange: NSRange
    package var closeRange: NSRange
    package var innerRange: NSRange
}

package enum JournalCode {
    package static func blocks(in text: String) -> [CodeBlock] {
        let ns = text as NSString
        // An unfinished fence is still code while the user is typing it.
        let pattern = #"(?m)^ {0,3}(`{3,}|~{3,})([^\n]*)\n?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fences = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result: [CodeBlock] = []
        var cursor = 0
        for fence in fences {
            guard fence.range.location >= cursor else { continue }
            let marker = ns.substring(with: fence.range(at: 1))
            let info = ns.substring(with: fence.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if marker.first == "`", info.contains("`") { continue }
            let closing = fences.first { candidate in
                guard candidate.range.location >= NSMaxRange(fence.range) else { return false }
                let value = ns.substring(with: candidate.range(at: 1))
                return value.first == marker.first && value.count >= marker.count && ns.substring(with: candidate.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let close = closing?.range ?? NSRange(location: ns.length, length: 0)
            result.append(CodeBlock(
                range: NSRange(location: fence.range.location, length: NSMaxRange(close) - fence.range.location),
                language: String(info.split(whereSeparator: \.isWhitespace).first ?? "").lowercased(),
                openRange: fence.range, closeRange: close,
                innerRange: NSRange(location: NSMaxRange(fence.range), length: close.location - NSMaxRange(fence.range))
            ))
            cursor = NSMaxRange(close)
        }
        return result
    }

    package static func spans(in text: String) -> [CodeSpan] {
        let ns = text as NSString
        let blocked = blocks(in: text)
        var spans: [CodeSpan] = []
        var index = 0
        while index < ns.length {
            if let block = blocked.first(where: { NSLocationInRange(index, $0.range) }) {
                index = NSMaxRange(block.range)
                continue
            }
            if ns.character(at: index) != 96 {
                index += 1
                continue
            }
            let ticks = tickCount(ns, index)
            var end = index + ticks
            var found = false
            while end < ns.length {
                let character = ns.character(at: end)
                if character == 10 { break }
                if character == 96 {
                    let closing = tickCount(ns, end)
                    if closing == ticks { found = true; break }
                    end += closing
                    continue
                }
                end += 1
            }
            if found, end > index + ticks {
                spans.append(CodeSpan(
                    range: NSRange(location: index, length: end + ticks - index),
                    innerRange: NSRange(location: index + ticks, length: end - (index + ticks))
                ))
                index = end + ticks
            } else {
                index += 1
            }
        }
        return spans
    }

    fileprivate static func tickCount(_ text: NSString, _ start: Int) -> Int {
        var ticks = 0
        while start + ticks < text.length, text.character(at: start + ticks) == 96 { ticks += 1 }
        return ticks
    }

    fileprivate static func isLineStart(_ text: NSString, _ index: Int) -> Bool {
        index == 0 || text.character(at: index - 1) == 10
    }

    fileprivate static func findFence(in text: NSString, from start: Int, ticks: Int) -> (start: Int, end: Int)? {
        var index = start
        while index < text.length {
            if isLineStart(text, index) {
                let found = tickCount(text, index)
                if found >= ticks {
                    var end = index + found
                    while end < text.length, text.character(at: end) == 32 || text.character(at: end) == 9 { end += 1 }
                    if end == text.length || text.character(at: end) == 10 {
                        return (index, end == text.length || text.character(at: end) != 10 ? end : end + 1)
                    }
                }
            }
            index += 1
        }
        return nil
    }
}

package enum JournalMath {
    package static func spans(in text: String) -> [MathSpan] {
        let ns = text as NSString
        let length = ns.length
        var spans: [MathSpan] = []
        let code = JournalCode.blocks(in: text).map(\.range) + JournalCode.spans(in: text).map(\.range)
        var index = 0
        while index < length {
            if let range = code.first(where: { NSLocationInRange(index, $0) }) { index = NSMaxRange(range); continue }
            let character = ns.character(at: index)
            if character == 96 {
                index = skipCode(in: ns, from: index)
                continue
            }
            if character == 36, !escaped(ns, at: index) {
                if index + 1 < length, ns.character(at: index + 1) == 36 {
                    if let end = findCloser(in: ns, from: index + 2, display: true) {
                        let inner = NSRange(location: index + 2, length: end - (index + 2))
                        spans.append(MathSpan(
                            range: NSRange(location: index, length: end + 2 - index),
                            latex: ns.substring(with: inner),
                            display: true
                        ))
                        index = end + 2
                        continue
                    }
                } else if let end = findCloser(in: ns, from: index + 1, display: false) {
                    let inner = NSRange(location: index + 1, length: end - (index + 1))
                    let latex = ns.substring(with: inner)
                    if !latex.isEmpty, !latex.contains(where: \.isNewline) {
                        spans.append(MathSpan(
                            range: NSRange(location: index, length: end + 1 - index),
                            latex: latex,
                            display: false
                        ))
                        index = end + 1
                        continue
                    }
                }
            }
            index += 1
        }
        return spans
    }

    private static func escaped(_ text: NSString, at index: Int) -> Bool {
        var previous = index - 1
        var count = 0
        while previous >= 0, text.character(at: previous) == 92 { count += 1; previous -= 1 }
        return count % 2 == 1
    }

    private static func skipCode(in text: NSString, from start: Int) -> Int {
        let ticks = JournalCode.tickCount(text, start)
        if ticks >= 3, JournalCode.isLineStart(text, start) {
            if let close = JournalCode.findFence(in: text, from: start + ticks, ticks: ticks) {
                return close.end
            }
            return text.length
        }
        var index = start + 1
        while index < text.length {
            if text.character(at: index) == 96 { return index + 1 }
            if text.character(at: index) == 10 { return index + 1 }
            index += 1
        }
        return text.length
    }

    private static func findCloser(in text: NSString, from start: Int, display: Bool) -> Int? {
        var index = start
        while index < text.length {
            let character = text.character(at: index)
            if character == 96 {
                index = skipCode(in: text, from: index)
                continue
            }
            if escaped(text, at: index) { index += 1; continue }
            if display {
                if character == 36, index + 1 < text.length, text.character(at: index + 1) == 36 {
                    return index
                }
            } else if character == 36 {
                if index + 1 < text.length, text.character(at: index + 1) == 36 { return nil }
                return index
            } else if character == 10 {
                return nil
            }
            index += 1
        }
        return nil
    }
}
