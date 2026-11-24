/// Reasons an expression cannot be evaluated.
enum EvaluationError: Error {
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
/// Parsing uses an explicit operator stack (operator-precedence parsing)
/// rather than recursion, so arbitrarily deep nesting cannot exhaust the
/// call stack.
struct Evaluator {
    private enum Operator {
        case add, subtract, multiply, divide, remainder, negate, openParen

        var precedence: Int {
            switch self {
            case .openParen: return 0
            case .add, .subtract: return 1
            case .multiply, .divide, .remainder: return 2
            case .negate: return 3
            }
        }
    }

    private var operands: [Int64] = []
    private var operators: [Operator] = []

    /// Evaluates a single expression given as UTF-8 bytes.
    mutating func evaluate<Bytes: Collection>(_ input: Bytes) throws(EvaluationError) -> Int64
    where Bytes.Element == UInt8 {
        operands.removeAll(keepingCapacity: true)
        operators.removeAll(keepingCapacity: true)

        var index = input.startIndex
        var expectingOperand = true

        while index != input.endIndex {
            let byte = input[index]

            if byte == .space || byte == .tab {
                input.formIndex(after: &index)
                continue
            }

            if expectingOperand {
                switch byte {
                case .zero ... .nine:
                    operands.append(try Self.parseNumber(input, from: &index))
                    expectingOperand = false
                    continue
                case .minus:
                    operators.append(.negate)
                case .openParen:
                    operators.append(.openParen)
                default:
                    throw .syntax
                }
            } else {
                switch byte {
                case .plus: try pushBinary(.add)
                case .minus: try pushBinary(.subtract)
                case .star: try pushBinary(.multiply)
                case .slash: try pushBinary(.divide)
                case .percent: try pushBinary(.remainder)
                case .closeParen:
                    try closeParenthesis()
                    input.formIndex(after: &index)
                    continue
                default:
                    throw .syntax
                }
                expectingOperand = true
            }
            input.formIndex(after: &index)
        }

        guard !expectingOperand else { throw .syntax }
        while let op = operators.popLast() {
            guard op != .openParen else { throw .syntax }
            try apply(op)
        }
        guard operands.count == 1 else { throw .syntax }
        return operands[0]
    }

    // MARK: - Parsing helpers

    private static func parseNumber<Bytes: Collection>(
        _ input: Bytes, from index: inout Bytes.Index
    ) throws(EvaluationError) -> Int64 where Bytes.Element == UInt8 {
        var value: Int64 = 0
        while index != input.endIndex {
            let byte = input[index]
            guard byte >= .zero, byte <= .nine else { break }
            let (scaled, o1) = value.multipliedReportingOverflow(by: 10)
            let (sum, o2) = scaled.addingReportingOverflow(Int64(byte - .zero))
            if o1 || o2 { throw .overflow }
            value = sum
            input.formIndex(after: &index)
        }
        return value
    }

    /// Reduces pending operators that bind at least as tightly as `op`
    /// (all binary operators are left-associative), then pushes `op`.
    private mutating func pushBinary(_ op: Operator) throws(EvaluationError) {
        while let top = operators.last, top.precedence >= op.precedence {
            operators.removeLast()
            try apply(top)
        }
        operators.append(op)
    }

    private mutating func closeParenthesis() throws(EvaluationError) {
        while let top = operators.popLast() {
            if top == .openParen { return }
            try apply(top)
        }
        throw .syntax
    }

    // MARK: - Arithmetic

    private mutating func apply(_ op: Operator) throws(EvaluationError) {
        if op == .negate {
            guard let value = operands.popLast() else { throw .syntax }
            let (result, overflow) = Int64(0).subtractingReportingOverflow(value)
            if overflow { throw .overflow }
            operands.append(result)
            return
        }

        guard let rhs = operands.popLast(), let lhs = operands.popLast() else { throw .syntax }
        operands.append(try Self.compute(op, lhs, rhs))
    }

    private static func compute(_ op: Operator, _ lhs: Int64, _ rhs: Int64) throws(EvaluationError) -> Int64 {
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
            // Int64.min % -1 is mathematically 0; avoid the trapping case.
            return rhs == -1 ? 0 : lhs % rhs
        case .negate, .openParen:
            throw .syntax
        }
        if overflow { throw .overflow }
        return result
    }
}

private extension UInt8 {
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let plus = UInt8(ascii: "+")
    static let minus = UInt8(ascii: "-")
    static let star = UInt8(ascii: "*")
    static let slash = UInt8(ascii: "/")
    static let percent = UInt8(ascii: "%")
    static let openParen = UInt8(ascii: "(")
    static let closeParen = UInt8(ascii: ")")
}
