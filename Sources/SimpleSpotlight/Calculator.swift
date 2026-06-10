import Foundation

final class Calculator {
    func evaluate(_ input: String) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeExpression(trimmed) else { return nil }
        var parser = Parser(trimmed)
        guard let value = parser.parse(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    private func looksLikeExpression(_ input: String) -> Bool {
        guard !input.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/^()% \t")
            .union(.letters)
        guard input.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return input.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789")) != nil &&
            input.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^()%")) != nil ||
            input.lowercased().contains("sqrt") ||
            input.lowercased().contains("sin") ||
            input.lowercased().contains("cos") ||
            input.lowercased().contains("tan") ||
            input.lowercased().contains("log") ||
            input.lowercased().contains("ln")
    }
}

private struct Parser {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(_ input: String) {
        scalars = Array(input.unicodeScalars)
    }

    var isAtEnd: Bool {
        var copy = self
        copy.skipWhitespace()
        return copy.index >= copy.scalars.count
    }

    mutating func parse() -> Double? {
        parseExpression()
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }
        while true {
            skipWhitespace()
            if consume("+") {
                guard let rhs = parseTerm() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = parseTerm() else { return nil }
                value -= rhs
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parsePower() else { return nil }
        while true {
            skipWhitespace()
            if consume("*") {
                guard let rhs = parsePower() else { return nil }
                value *= rhs
            } else if consume("/") {
                guard let rhs = parsePower(), rhs != 0 else { return nil }
                value /= rhs
            } else if consume("%") {
                value /= 100
            } else {
                return value
            }
        }
    }

    private mutating func parsePower() -> Double? {
        guard var value = parseUnary() else { return nil }
        skipWhitespace()
        if consume("^") {
            guard let rhs = parsePower() else { return nil }
            value = pow(value, rhs)
        }
        return value
    }

    private mutating func parseUnary() -> Double? {
        skipWhitespace()
        if consume("+") { return parseUnary() }
        if consume("-") { return parseUnary().map { -$0 } }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        skipWhitespace()

        if consume("(") {
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            guard consume(")") else { return nil }
            return value
        }

        if let number = parseNumber() {
            return number
        }

        if let identifier = parseIdentifier() {
            switch identifier {
            case "pi": return Double.pi
            case "e": return Darwin.M_E
            case "sqrt", "sin", "cos", "tan", "log", "ln":
                skipWhitespace()
                guard consume("("), let argument = parseExpression() else { return nil }
                skipWhitespace()
                guard consume(")") else { return nil }
                switch identifier {
                case "sqrt": return argument >= 0 ? Foundation.sqrt(argument) : nil
                case "sin": return Foundation.sin(argument)
                case "cos": return Foundation.cos(argument)
                case "tan": return Foundation.tan(argument)
                case "log": return argument > 0 ? Foundation.log10(argument) : nil
                case "ln": return argument > 0 ? Foundation.log(argument) : nil
                default: return nil
                }
            default:
                return nil
            }
        }

        return nil
    }

    private mutating func parseNumber() -> Double? {
        skipWhitespace()
        let start = index
        var hasDigit = false
        var hasDot = false

        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.decimalDigits.contains(scalar) {
                hasDigit = true
                index += 1
            } else if scalar == ".", !hasDot {
                hasDot = true
                index += 1
            } else {
                break
            }
        }

        guard hasDigit else {
            index = start
            return nil
        }

        return Double(String(String.UnicodeScalarView(scalars[start..<index])))
    }

    private mutating func parseIdentifier() -> String? {
        skipWhitespace()
        let start = index
        while index < scalars.count, CharacterSet.letters.contains(scalars[index]) {
            index += 1
        }
        guard index > start else { return nil }
        return String(String.UnicodeScalarView(scalars[start..<index])).lowercased()
    }

    private mutating func consume(_ token: UnicodeScalar) -> Bool {
        skipWhitespace()
        guard index < scalars.count, scalars[index] == token else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < scalars.count, CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
            index += 1
        }
    }
}
