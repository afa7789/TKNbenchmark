/// Why an expression could not be evaluated.
public enum CalcError: Error, Equatable, Sendable {
    case syntax
    case divisionByZero
    case overflow
}

/// Evaluates 64-bit signed integer expressions:
///
///     expr    := term    (('+' | '-') term)*
///     term    := unary   (('*' | '/' | '%') unary)*
///     unary   := '-' unary | primary
///     primary := NUMBER | '(' expr ')'
///
/// Parsing uses an explicit operator stack (shunting-yard), so deeply nested
/// input cannot exhaust the call stack.
public enum Calculator {
    /// Whether the line contains only spaces and tabs (and should produce no output).
    public static func isBlank(_ bytes: some Sequence<UInt8>) -> Bool {
        bytes.allSatisfy(isSpace)
    }

    public static func evaluate(_ text: String) -> Result<Int64, CalcError> {
        var text = text
        return text.withUTF8 { evaluate($0) }
    }

    public static func evaluate(_ bytes: UnsafeBufferPointer<UInt8>) -> Result<Int64, CalcError> {
        do {
            var evaluator = Evaluator()
            return .success(try evaluator.run(bytes))
        } catch {
            return .failure(error)
        }
    }

    @inline(__always)
    static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }
}

private enum Operator {
    case negate, add, subtract, multiply, divide, remainder, openParen

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

    /// Binding strength; an open parenthesis is never reduced by an operator.
    var precedence: Int {
        switch self {
        case .openParen: 0
        case .add, .subtract: 1
        case .multiply, .divide, .remainder: 2
        case .negate: 3
        }
    }
}

private struct Evaluator {
    private var values: [Int64] = []
    private var operators: [Operator] = []

    mutating func run(_ bytes: UnsafeBufferPointer<UInt8>) throws(CalcError) -> Int64 {
        var index = bytes.startIndex
        var expectingOperand = true

        while index < bytes.endIndex {
            let byte = bytes[index]
            if Calculator.isSpace(byte) {
                index += 1
                continue
            }

            if expectingOperand {
                switch byte {
                case UInt8(ascii: "-"):
                    operators.append(.negate)
                    index += 1
                case UInt8(ascii: "("):
                    operators.append(.openParen)
                    index += 1
                case UInt8(ascii: "0")...UInt8(ascii: "9"):
                    values.append(try Self.parseNumber(bytes, at: &index))
                    expectingOperand = false
                default:
                    throw .syntax
                }
            } else if byte == UInt8(ascii: ")") {
                try reduce(whileAtLeast: 1)
                guard operators.popLast() == .openParen else { throw .syntax }
                index += 1
            } else if let op = Operator(binary: byte) {
                try reduce(whileAtLeast: op.precedence)
                operators.append(op)
                expectingOperand = true
                index += 1
            } else {
                throw .syntax
            }
        }

        guard !expectingOperand else { throw .syntax }
        try reduce(whileAtLeast: 1)
        guard operators.isEmpty, values.count == 1 else { throw .syntax }
        return values[0]
    }

    /// Applies stacked operators whose precedence is at least `minimum`
    /// (left associativity for binary operators; prefix negation always binds first).
    private mutating func reduce(whileAtLeast minimum: Int) throws(CalcError) {
        while let op = operators.last, op.precedence >= minimum {
            operators.removeLast()
            try apply(op)
        }
    }

    private mutating func apply(_ op: Operator) throws(CalcError) {
        if op == .negate {
            guard let operand = values.popLast() else { throw .syntax }
            let (result, overflow) = Int64(0).subtractingReportingOverflow(operand)
            guard !overflow else { throw .overflow }
            values.append(result)
            return
        }
        guard let rhs = values.popLast(), let lhs = values.popLast() else { throw .syntax }
        values.append(try Self.binary(op, lhs, rhs))
    }

    private static func binary(_ op: Operator, _ lhs: Int64, _ rhs: Int64) throws(CalcError) -> Int64 {
        let (result, overflow): (Int64, Bool)
        switch op {
        case .add:
            (result, overflow) = lhs.addingReportingOverflow(rhs)
        case .subtract:
            (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        case .multiply:
            (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        case .divide:
            guard rhs != 0 else { throw .divisionByZero }
            (result, overflow) = lhs.dividedReportingOverflow(by: rhs)
        case .remainder:
            guard rhs != 0 else { throw .divisionByZero }
            // Int64.min % -1 is mathematically 0; only the hardware division overflows.
            (result, overflow) = rhs == -1 ? (0, false) : lhs.remainderReportingOverflow(dividingBy: rhs)
        case .negate, .openParen:
            preconditionFailure("not a binary operator: \(op)")
        }
        guard !overflow else { throw .overflow }
        return result
    }

    private static func parseNumber(
        _ bytes: UnsafeBufferPointer<UInt8>, at index: inout Int
    ) throws(CalcError) -> Int64 {
        var value: Int64 = 0
        var overflow = false
        while index < bytes.endIndex, case UInt8(ascii: "0")...UInt8(ascii: "9") = bytes[index] {
            if !overflow {
                let (scaled, o1) = value.multipliedReportingOverflow(by: 10)
                let (sum, o2) = scaled.addingReportingOverflow(Int64(bytes[index] &- UInt8(ascii: "0")))
                overflow = o1 || o2
                value = sum
            }
            index += 1
        }
        guard !overflow else { throw .overflow }
        return value
    }
}
