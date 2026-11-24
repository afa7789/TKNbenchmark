/// Reasons an expression can fail to evaluate.
enum EvaluationError: Error, Equatable {
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
/// The evaluator is an operator-precedence (shunting-yard) machine with explicit
/// stacks, so arbitrarily deep nesting cannot exhaust the call stack.
struct Evaluator {
    private enum BinaryOperator {
        case add, subtract, multiply, divide, remainder

        init?(byte: UInt8) {
            switch byte {
            case UInt8(ascii: "+"): self = .add
            case UInt8(ascii: "-"): self = .subtract
            case UInt8(ascii: "*"): self = .multiply
            case UInt8(ascii: "/"): self = .divide
            case UInt8(ascii: "%"): self = .remainder
            default: return nil
            }
        }

        var precedence: Int {
            switch self {
            case .add, .subtract: return 1
            case .multiply, .divide, .remainder: return 2
            }
        }

        func apply(_ lhs: Int64, _ rhs: Int64) throws(EvaluationError) -> Int64 {
            let result: (partialValue: Int64, overflow: Bool)
            switch self {
            case .add:
                result = lhs.addingReportingOverflow(rhs)
            case .subtract:
                result = lhs.subtractingReportingOverflow(rhs)
            case .multiply:
                result = lhs.multipliedReportingOverflow(by: rhs)
            case .divide:
                guard rhs != 0 else { throw .divisionByZero }
                result = lhs.dividedReportingOverflow(by: rhs)
            case .remainder:
                guard rhs != 0 else { throw .divisionByZero }
                // Int64.min % -1 is mathematically 0; only the quotient overflows.
                if rhs == -1 { return 0 }
                result = lhs.remainderReportingOverflow(dividingBy: rhs)
            }
            guard !result.overflow else { throw .overflow }
            return result.partialValue
        }
    }

    private enum StackOperator {
        case negate
        case binary(BinaryOperator)
        case openParen
    }

    private var operands: [Int64] = []
    private var operators: [StackOperator] = []

    /// Evaluates one expression given as UTF-8 bytes.
    /// - Returns: `nil` if the line is blank (only spaces and tabs).
    mutating func evaluate<Bytes: Collection>(
        _ bytes: Bytes
    ) throws(EvaluationError) -> Int64? where Bytes.Element == UInt8 {
        operands.removeAll(keepingCapacity: true)
        operators.removeAll(keepingCapacity: true)

        var expectingOperand = true
        var sawToken = false
        var index = bytes.startIndex

        while index != bytes.endIndex {
            let byte = bytes[index]

            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") {
                bytes.formIndex(after: &index)
                continue
            }
            sawToken = true

            if expectingOperand {
                if let digit = Self.digitValue(byte) {
                    var value = Int64(digit)
                    bytes.formIndex(after: &index)
                    while index != bytes.endIndex, let next = Self.digitValue(bytes[index]) {
                        let shifted = value.multipliedReportingOverflow(by: 10)
                        let sum = shifted.partialValue.addingReportingOverflow(Int64(next))
                        guard !shifted.overflow, !sum.overflow else { throw .overflow }
                        value = sum.partialValue
                        bytes.formIndex(after: &index)
                    }
                    operands.append(value)
                    expectingOperand = false
                    continue
                }
                switch byte {
                case UInt8(ascii: "-"): operators.append(.negate)
                case UInt8(ascii: "("): operators.append(.openParen)
                default: throw .syntax
                }
            } else if let op = BinaryOperator(byte: byte) {
                try reduce(whileAtLeast: op.precedence)
                operators.append(.binary(op))
                expectingOperand = true
            } else if byte == UInt8(ascii: ")") {
                try reduce(whileAtLeast: 0)
                guard case .openParen? = operators.popLast() else { throw .syntax }
            } else {
                throw .syntax
            }
            bytes.formIndex(after: &index)
        }

        guard sawToken else { return nil }
        guard !expectingOperand else { throw .syntax }
        try reduce(whileAtLeast: 0)
        guard operators.isEmpty, operands.count == 1 else { throw .syntax }
        return operands[0]
    }

    /// Applies stacked operators down to the nearest open parenthesis while their
    /// precedence is at least `minimum`. Unary negation binds tighter than any
    /// binary operator, and equal precedence reduces first (left associativity).
    private mutating func reduce(whileAtLeast minimum: Int) throws(EvaluationError) {
        while let top = operators.last {
            switch top {
            case .openParen:
                return
            case .negate:
                let value = operands.removeLast()
                guard value != .min else { throw .overflow }
                operands.append(-value)
            case .binary(let op):
                guard op.precedence >= minimum else { return }
                let rhs = operands.removeLast()
                let lhs = operands.removeLast()
                operands.append(try op.apply(lhs, rhs))
            }
            operators.removeLast()
        }
    }

    private static func digitValue(_ byte: UInt8) -> UInt8? {
        let value = byte &- UInt8(ascii: "0")
        return value < 10 ? value : nil
    }
}
