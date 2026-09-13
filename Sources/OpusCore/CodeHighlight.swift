import Foundation

package enum CodeTokenKind: Equatable, Sendable {
    case comment, string, number, keyword, type, attribute
}

package enum CodeHighlight {
    package static func tokens(in text: String, language: String) -> [(NSRange, CodeTokenKind)] {
        let ns = text as NSString
        let family = Family.of(language)
        var tokens: [(NSRange, CodeTokenKind)] = []
        var index = 0
        while index < ns.length {
            let character = ns.character(at: index)
            if character == 32 || character == 9 || character == 10 || character == 13 {
                index += 1
                continue
            }
            if let range = comment(in: ns, from: index, family: family) {
                tokens.append((range, .comment))
                index = NSMaxRange(range)
                continue
            }
            if let range = string(in: ns, from: index, family: family) {
                tokens.append((range, .string))
                index = NSMaxRange(range)
                continue
            }
            if let range = number(in: ns, from: index) {
                tokens.append((range, .number))
                index = NSMaxRange(range)
                continue
            }
            if family == .html, character == 60, let range = htmlTag(in: ns, from: index) {
                tokens.append((range, .keyword))
                index = NSMaxRange(range)
                continue
            }
            if character == 64, family == .clike {
                let end = identEnd(in: ns, from: index + 1)
                tokens.append((NSRange(location: index, length: end - index), .attribute))
                index = end
                continue
            }
            if isIdentStart(character) {
                let end = identEnd(in: ns, from: index)
                let word = ns.substring(with: NSRange(location: index, length: end - index))
                if family.keywords.contains(word) {
                    tokens.append((NSRange(location: index, length: end - index), .keyword))
                } else if family.types.contains(word) || (word.first?.isUppercase == true && family == .clike) {
                    tokens.append((NSRange(location: index, length: end - index), .type))
                }
                index = end
                continue
            }
            index += 1
        }
        return tokens
    }

    private enum Family {
        case clike, python, bash, ruby, html, json, sql, css, generic

        var keywords: Set<String> {
            switch self {
            case .clike:
                ["func", "function", "fn", "let", "var", "const", "if", "else", "for", "while", "return", "class", "struct", "enum", "protocol", "extension", "import", "from", "as", "try", "catch", "throw", "guard", "switch", "case", "break", "continue", "in", "where", "async", "await", "true", "false", "nil", "null", "undefined", "new", "this", "self", "super", "pub", "public", "private", "static", "mut", "impl", "mod", "use", "crate", "type", "typedef", "void", "int", "char", "bool", "package", "interface", "defer", "go", "chan", "map", "range", "match", "lambda", "def", "yield"]
            case .python:
                ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "async", "await", "True", "False", "None", "and", "or", "not", "in", "is", "pass", "break", "continue", "global", "nonlocal"]
            case .bash:
                ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "in", "function", "return", "local", "export", "unset", "echo", "cd", "true", "false"]
            case .ruby:
                ["def", "class", "module", "if", "elsif", "else", "end", "unless", "while", "until", "for", "do", "return", "yield", "begin", "rescue", "ensure", "true", "false", "nil", "self", "and", "or", "not"]
            case .sql:
                ["select", "from", "where", "insert", "into", "update", "set", "delete", "create", "table", "alter", "drop", "join", "left", "right", "inner", "on", "and", "or", "not", "null", "as", "order", "by", "group", "having", "limit", "values", "primary", "key"]
            case .css:
                ["important", "none", "auto", "inherit", "initial", "unset", "block", "flex", "grid", "absolute", "relative", "fixed"]
            case .json:
                ["true", "false", "null"]
            case .html, .generic:
                []
            }
        }

        var types: Set<String> {
            switch self {
            case .clike:
                ["String", "Int", "Int32", "Int64", "Double", "Float", "Bool", "Array", "Dictionary", "Optional", "Any", "Self", "Error", "Result", "Option", "Vec", "String", "boolean", "number", "string"]
            case .python:
                ["int", "str", "float", "bool", "list", "dict", "tuple", "set"]
            default:
                []
            }
        }

        static func of(_ language: String) -> Family {
            switch language {
            case "swift", "js", "javascript", "ts", "typescript", "jsx", "tsx", "rust", "rs", "go", "c", "h", "cpp", "c++", "cc", "java", "kt", "kotlin", "cs", "csharp":
                .clike
            case "py", "python":
                .python
            case "bash", "sh", "zsh", "shell":
                .bash
            case "rb", "ruby":
                .ruby
            case "html", "xml", "svg":
                .html
            case "json":
                .json
            case "sql":
                .sql
            case "css", "scss":
                .css
            default:
                language.isEmpty ? .generic : .clike
            }
        }
    }

    private static func isIdentStart(_ character: unichar) -> Bool {
        character == 95 || (character >= 65 && character <= 90) || (character >= 97 && character <= 122)
    }

    private static func isIdent(_ character: unichar) -> Bool {
        isIdentStart(character) || (character >= 48 && character <= 57)
    }

    private static func identEnd(in text: NSString, from start: Int) -> Int {
        var index = start
        while index < text.length, isIdent(text.character(at: index)) { index += 1 }
        return index
    }

    private static func comment(in text: NSString, from start: Int, family: Family) -> NSRange? {
        let character = text.character(at: start)
        if family == .html, character == 60, start + 3 < text.length,
           text.substring(with: NSRange(location: start, length: 4)) == "<!--" {
            var index = start + 4
            while index + 2 < text.length {
                if text.character(at: index) == 45, text.character(at: index + 1) == 45, text.character(at: index + 2) == 62 {
                    return NSRange(location: start, length: index + 3 - start)
                }
                index += 1
            }
            return NSRange(location: start, length: text.length - start)
        }
        if (family == .python || family == .bash || family == .ruby || family == .generic), character == 35 {
            return line(in: text, from: start)
        }
        if family == .sql, start + 1 < text.length, character == 45, text.character(at: start + 1) == 45 {
            return line(in: text, from: start)
        }
        if family == .clike || family == .css || family == .sql || family == .generic {
            if start + 1 < text.length, character == 47, text.character(at: start + 1) == 47 {
                return line(in: text, from: start)
            }
            if start + 1 < text.length, character == 47, text.character(at: start + 1) == 42 {
                var index = start + 2
                while index + 1 < text.length {
                    if text.character(at: index) == 42, text.character(at: index + 1) == 47 {
                        return NSRange(location: start, length: index + 2 - start)
                    }
                    index += 1
                }
                return NSRange(location: start, length: text.length - start)
            }
        }
        return nil
    }

    private static func line(in text: NSString, from start: Int) -> NSRange {
        var index = start
        while index < text.length, text.character(at: index) != 10 { index += 1 }
        return NSRange(location: start, length: index - start)
    }

    private static func string(in text: NSString, from start: Int, family: Family) -> NSRange? {
        let character = text.character(at: start)
        if family == .python || family == .generic, start + 2 < text.length,
           (character == 34 || character == 39),
           text.character(at: start + 1) == character,
           text.character(at: start + 2) == character {
            var index = start + 3
            while index + 2 < text.length {
                if text.character(at: index) == character,
                   text.character(at: index + 1) == character,
                   text.character(at: index + 2) == character {
                    return NSRange(location: start, length: index + 3 - start)
                }
                index += 1
            }
            return NSRange(location: start, length: text.length - start)
        }
        if character == 34 || character == 39 {
            if family == .clike, character == 39, start + 1 < text.length, isIdentStart(text.character(at: start + 1)) {
                return nil
            }
            var index = start + 1
            while index < text.length {
                let next = text.character(at: index)
                if next == 10 { break }
                if next == 92 {
                    index += 2
                    continue
                }
                if next == character {
                    return NSRange(location: start, length: index + 1 - start)
                }
                index += 1
            }
            return NSRange(location: start, length: index - start)
        }
        return nil
    }

    private static func number(in text: NSString, from start: Int) -> NSRange? {
        let character = text.character(at: start)
        guard character >= 48 && character <= 57 else { return nil }
        var index = start + 1
        while index < text.length {
            let next = text.character(at: index)
            if (next >= 48 && next <= 57) || next == 46 || next == 95 || next == 120 || next == 98 || next == 111 {
                index += 1
            } else {
                break
            }
        }
        return NSRange(location: start, length: index - start)
    }

    private static func htmlTag(in text: NSString, from start: Int) -> NSRange? {
        var index = start + 1
        while index < text.length {
            let character = text.character(at: index)
            if character == 62 { return NSRange(location: start, length: index + 1 - start) }
            if character == 10 { break }
            index += 1
        }
        return nil
    }
}
