/// Why an expression could not be evaluated.
public enum CalcError: Error, Equatable, Sendable {
    case syntax
    case divisionByZero
    case overflow
}

/// Evaluates 64-bit signed integer expressions.
///
/// Grammar:
/// ```
/// expr    := term    (('+' | '-') term)*
/// term    := unary   (('*' | '/' | '%') unary)*
/// unary   := '-' unary | primary
/// primary := NUMBER | '(' expr ')'
/// ```
///
/// Parsing uses an explicit operator stack (shunting-yard) rather than
/// recursion, so arbitrarily deep nesting cannot overflow the call stack.
public enum Calculator {
    /// Evaluates one input line (without its terminating newline).
    /// Returns `nil` for a blank line (empty or only spaces/tabs).
    public static func evaluateLine(_ line: Substring) -> Result<Int64, CalcError>? {
        let bytes = line.utf8
        guard bytes.contains(where: { !isBlank($0) }) else { return nil }
        return Result { () throws(CalcError) in try evaluate(bytes) }
    }

    /// Evaluates one input line (without its terminating newline).
    /// Returns `nil` for a blank line (empty or only spaces/tabs).
    public static func evaluateLine(_ line: String) -> Result<Int64, CalcError>? {
        evaluateLine(Substring(line))
    }

    /// Evaluates a single expression.
    public static func evaluate(_ expression: String) throws(CalcError) -> Int64 {
        try evaluate(Substring(expression).utf8)
    }

    private static func evaluate(_ bytes: Substring.UTF8View) throws(CalcError) -> Int64 {
        var evaluator = Evaluator()
        var index = bytes.startIndex
        while index != bytes.endIndex {
            let byte = bytes[index]
            if isBlank(byte) {
                bytes.formIndex(after: &index)
            } else if isDigit(byte) {
                var value: Int64 = 0
                while index != bytes.endIndex, isDigit(bytes[index]) {
                    let digit = Int64(bytes[index] &- asciiZero)
                    let (scaled, o1) = value.multipliedReportingOverflow(by: 10)
                    let (sum, o2) = scaled.addingReportingOverflow(digit)
                    guard !o1, !o2 else { throw .overflow }
                    value = sum
                    bytes.formIndex(after: &index)
                }
                try evaluator.operand(value)
            } else {
                try evaluator.symbol(byte)
                bytes.formIndex(after: &index)
            }
        }
        return try evaluator.finish()
    }

    private static let asciiZero = UInt8(ascii: "0")

    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (asciiZero...UInt8(ascii: "9")).contains(byte)
    }
}

// MARK: - Shunting-yard evaluator

private enum Operator {
    case add, subtract, multiply, divide, remainder, negate, openParen

    /// Binding strength; higher binds tighter. Parentheses never pop.
    var precedence: Int {
        switch self {
        case .openParen: 0
        case .add, .subtract: 1
        case .multiply, .divide, .remainder: 2
        case .negate: 3
        }
    }

    init?(binary byte: UInt8) {
        switch byte {
        case UInt8(ascii: "+"): self = .add
        case UInt8(ascii: "-"): self = .subtract
        case UInt8(ascii: "*"): self = .multiply
        case UInt8(ascii: "/"): self = .divide
        case UInt8(ascii: "%"): self = .remainder
        default: return nil
        }
    }
}

private struct Evaluator {
    private var values: [Int64] = []
    private var operators: [Operator] = []
    /// `true` when the next token must start an operand (number, `-`, or `(`).
    private var expectingOperand = true

    mutating func operand(_ value: Int64) throws(CalcError) {
        guard expectingOperand else { throw .syntax }
        values.append(value)
        expectingOperand = false
    }

    mutating func symbol(_ byte: UInt8) throws(CalcError) {
        if expectingOperand {
            switch byte {
            case UInt8(ascii: "-"): operators.append(.negate)
            case UInt8(ascii: "("): operators.append(.openParen)
            default: throw .syntax
            }
            return
        }
        if byte == UInt8(ascii: ")") {
            try reduce(whileAtLeast: 1)
            guard operators.popLast() == .openParen else { throw .syntax }
            return
        }
        guard let op = Operator(binary: byte) else { throw .syntax }
        // All binary operators are left-associative: reduce equal precedence first.
        try reduce(whileAtLeast: op.precedence)
        operators.append(op)
        expectingOperand = true
    }

    mutating func finish() throws(CalcError) -> Int64 {
        guard !expectingOperand else { throw .syntax }
        try reduce(whileAtLeast: 1)
        guard operators.isEmpty, values.count == 1 else { throw .syntax }
        return values[0]
    }

    private mutating func reduce(whileAtLeast precedence: Int) throws(CalcError) {
        while let top = operators.last, top.precedence >= precedence {
            operators.removeLast()
            try apply(top)
        }
    }

    private mutating func apply(_ op: Operator) throws(CalcError) {
        if op == .negate {
            guard let value = values.popLast() else { throw .syntax }
            guard value != .min else { throw .overflow }
            values.append(-value)
            return
        }
        guard let rhs = values.popLast(), let lhs = values.popLast() else { throw .syntax }
        values.append(try Self.compute(op, lhs, rhs))
    }

    private static func compute(_ op: Operator, _ lhs: Int64, _ rhs: Int64) throws(CalcError) -> Int64 {
        let (result, overflow): (Int64, Bool)
        switch op {
        case .add: (result, overflow) = lhs.addingReportingOverflow(rhs)
        case .subtract: (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        case .multiply: (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        case .divide:
            guard rhs != 0 else { throw .divisionByZero }
            (result, overflow) = lhs.dividedReportingOverflow(by: rhs)
        case .remainder:
            guard rhs != 0 else { throw .divisionByZero }
            // `Int64.min % -1` is mathematically 0; only the quotient overflows.
            result = rhs == -1 ? 0 : lhs % rhs
            overflow = false
        case .negate, .openParen:
            preconditionFailure("\(op) is not a binary operator")
        }
        guard !overflow else { throw .overflow }
        return result
    }
}
