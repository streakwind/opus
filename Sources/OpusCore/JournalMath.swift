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
    package var openRange: NSRange { NSRange(location: range.location, length: 1) }
    package var closeRange: NSRange { NSRange(location: NSMaxRange(range) - 1, length: 1) }
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
        var blocks: [CodeBlock] = []
        var index = 0
        while index < ns.length {
            guard isLineStart(ns, index) else {
                index += 1
                continue
            }
            let ticks = tickCount(ns, index)
            guard ticks >= 3 else {
                index += 1
                continue
            }
            let infoStart = index + ticks
            var infoEnd = infoStart
            while infoEnd < ns.length, ns.character(at: infoEnd) != 10 { infoEnd += 1 }
            guard infoEnd < ns.length else { break }
            let language = ns.substring(with: NSRange(location: infoStart, length: infoEnd - infoStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let openEnd = infoEnd + 1
            guard let close = findFence(in: ns, from: openEnd, ticks: ticks) else {
                index = openEnd
                continue
            }
            blocks.append(CodeBlock(
                range: NSRange(location: index, length: close.end - index),
                language: language,
                openRange: NSRange(location: index, length: openEnd - index),
                closeRange: NSRange(location: close.start, length: close.end - close.start),
                innerRange: NSRange(location: openEnd, length: close.start - openEnd)
            ))
            index = close.end
        }
        return blocks
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
            if ticks != 1 {
                index += ticks
                continue
            }
            var end = index + 1
            var found = false
            while end < ns.length {
                let character = ns.character(at: end)
                if character == 10 { break }
                if character == 96 {
                    found = true
                    break
                }
                end += 1
            }
            if found, end > index + 1 {
                spans.append(CodeSpan(
                    range: NSRange(location: index, length: end + 1 - index),
                    innerRange: NSRange(location: index + 1, length: end - (index + 1))
                ))
                index = end + 1
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
        var index = 0
        while index < length {
            let character = ns.character(at: index)
            if character == 96 {
                index = skipCode(in: ns, from: index)
                continue
            }
            if character == 36 {
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
