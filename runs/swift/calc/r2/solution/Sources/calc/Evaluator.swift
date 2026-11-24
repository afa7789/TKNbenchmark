/// Errors that make an expression evaluate to `error`.
enum EvaluationError: Error, Equatable {
    case syntax
    case divisionByZero
    case overflow
}

/// Evaluates 64-bit signed integer expressions following the grammar:
///
///     expr    := term    (('+' | '-') term)*
///     term    := unary   (('*' | '/' | '%') unary)*
///     unary   := '-' unary | primary
///     primary := NUMBER | '(' expr ')'
///
/// The parser is an iterative operator-precedence (shunting-yard) parser, so
/// arbitrarily deep nesting cannot overflow the call stack.
struct Evaluator {
    private enum Operator {
        case add, subtract, multiply, divide, remainder
        case negate
        case openParen

        /// Binding strength; higher binds tighter. Parentheses never reduce.
        var precedence: Int {
            switch self {
            case .add, .subtract: return 1
            case .multiply, .divide, .remainder: return 2
            case .negate: return 3
            case .openParen: return 0
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

    private var operands: [Int64] = []
    private var operators: [Operator] = []

    init() {
        operands.reserveCapacity(64)
        operators.reserveCapacity(64)
    }

    /// Returns `true` if the line contains only spaces and tabs.
    static func isBlank<C: Collection>(_ bytes: C) -> Bool where C.Element == UInt8 {
        bytes.allSatisfy(isWhitespace)
    }

    /// Evaluates one expression given as UTF-8 bytes.
    mutating func evaluate<C: Collection>(_ bytes: C) -> Result<Int64, EvaluationError>
    where C.Element == UInt8 {
        operands.removeAll(keepingCapacity: true)
        operators.removeAll(keepingCapacity: true)
        do {
            return .success(try parse(bytes))
        } catch let error as EvaluationError {
            return .failure(error)
        } catch {
            preconditionFailure("unexpected error: \(error)")
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private mutating func parse<C: Collection>(_ bytes: C) throws(EvaluationError) -> Int64
    where C.Element == UInt8 {
        var index = bytes.startIndex
        var expectingOperand = true

        while index != bytes.endIndex {
            let byte = bytes[index]

            if Self.isWhitespace(byte) {
                bytes.formIndex(after: &index)
                continue
            }

            if expectingOperand {
                switch byte {
                case UInt8(ascii: "-"):
                    operators.append(.negate)
                case UInt8(ascii: "("):
                    operators.append(.openParen)
                case _ where Self.isDigit(byte):
                    operands.append(try Self.parseNumber(bytes, from: &index))
                    expectingOperand = false
                    continue
                default:
                    throw .syntax
                }
            } else if byte == UInt8(ascii: ")") {
                try reduce(whileAtLeast: 1)
                guard operators.popLast() == .openParen else { throw .syntax }
            } else if let op = Operator(binary: byte) {
                // Left-associative: reduce operators of equal or higher precedence.
                try reduce(whileAtLeast: op.precedence)
                operators.append(op)
                expectingOperand = true
            } else {
                throw .syntax
            }
            bytes.formIndex(after: &index)
        }

        guard !expectingOperand else { throw .syntax }
        try reduce(whileAtLeast: 1)
        guard operators.isEmpty, operands.count == 1 else { throw .syntax }
        return operands[0]
    }

    /// Parses a run of decimal digits starting at `index`, advancing past it.
    private static func parseNumber<C: Collection>(
        _ bytes: C, from index: inout C.Index
    ) throws(EvaluationError) -> Int64 where C.Element == UInt8 {
        var value: Int64 = 0
        while index != bytes.endIndex, isDigit(bytes[index]) {
            let digit = Int64(bytes[index] &- UInt8(ascii: "0"))
            let (shifted, o1) = value.multipliedReportingOverflow(by: 10)
            let (sum, o2) = shifted.addingReportingOverflow(digit)
            guard !o1, !o2 else { throw .overflow }
            value = sum
            bytes.formIndex(after: &index)
        }
        return value
    }

    /// Applies stacked operators whose precedence is at least `minimum`.
    private mutating func reduce(whileAtLeast minimum: Int) throws(EvaluationError) {
        while let op = operators.last, op.precedence >= minimum {
            operators.removeLast()
            try apply(op)
        }
    }

    private mutating func apply(_ op: Operator) throws(EvaluationError) {
        if op == .negate {
            guard let value = operands.popLast() else { throw .syntax }
            let (result, overflow) = Int64(0).subtractingReportingOverflow(value)
            guard !overflow else { throw .overflow }
            operands.append(result)
            return
        }

        guard let rhs = operands.popLast(), let lhs = operands.popLast() else { throw .syntax }
        let result: (partialValue: Int64, overflow: Bool)
        switch op {
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
            // Int64.min % -1 is mathematically 0; the stdlib reports it as overflow.
            result = rhs == -1 ? (0, false) : lhs.remainderReportingOverflow(dividingBy: rhs)
        case .negate, .openParen:
            preconditionFailure("not a binary operator: \(op)")
        }
        guard !result.overflow else { throw .overflow }
        operands.append(result.partialValue)
    }
}
