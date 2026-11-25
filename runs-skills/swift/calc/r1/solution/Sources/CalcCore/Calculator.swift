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
/// Parsing uses an explicit operator stack (shunting-yard) rather than
/// recursion, so arbitrarily deep nesting cannot overflow the call stack.
public enum Calculator {
    /// Evaluates one input line (without its trailing newline).
    /// Returns `nil` when the line is blank (only spaces/tabs).
    public static func evaluateLine(_ bytes: some Collection<UInt8>) -> Result<Int64, CalcError>? {
        guard bytes.contains(where: { !isBlank($0) }) else { return nil }
        do {
            return .success(try evaluate(bytes))
        } catch {
            return .failure(error)
        }
    }

    /// Evaluates an expression, throwing on syntax errors, division by zero or overflow.
    public static func evaluate(_ bytes: some Collection<UInt8>) throws(CalcError) -> Int64 {
        var evaluator = Evaluator()
        var index = bytes.startIndex

        while index != bytes.endIndex {
            let byte = bytes[index]
            if isBlank(byte) {
                bytes.formIndex(after: &index)
                continue
            }
            if isDigit(byte) {
                var value: Int64 = 0
                var overflow = false
                while index != bytes.endIndex, isDigit(bytes[index]) {
                    if !overflow {
                        let (scaled, o1) = value.multipliedReportingOverflow(by: 10)
                        let (sum, o2) = scaled.addingReportingOverflow(Int64(bytes[index] &- UInt8(ascii: "0")))
                        overflow = o1 || o2
                        value = sum
                    }
                    bytes.formIndex(after: &index)
                }
                // Finish scanning the literal first so a later syntax error is not masked;
                // either way the line is an error.
                if overflow { throw .overflow }
                try evaluator.operand(value)
                continue
            }
            switch byte {
            case UInt8(ascii: "("): try evaluator.openParen()
            case UInt8(ascii: ")"): try evaluator.closeParen()
            case UInt8(ascii: "-"): try evaluator.minus()
            case UInt8(ascii: "+"): try evaluator.binary(.add)
            case UInt8(ascii: "*"): try evaluator.binary(.multiply)
            case UInt8(ascii: "/"): try evaluator.binary(.divide)
            case UInt8(ascii: "%"): try evaluator.binary(.remainder)
            default: throw .syntax
            }
            bytes.formIndex(after: &index)
        }
        return try evaluator.finish()
    }

    @inline(__always)
    private static func isBlank(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    @inline(__always)
    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}

// MARK: - Shunting-yard evaluator

private enum BinaryOperator {
    case add, subtract, multiply, divide, remainder

    var precedence: Int {
        switch self {
        case .add, .subtract: 1
        case .multiply, .divide, .remainder: 2
        }
    }

    func apply(_ lhs: Int64, _ rhs: Int64) throws(CalcError) -> Int64 {
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
            // Int64.min % -1 is mathematically 0; it is not an overflow.
            return rhs == -1 ? 0 : lhs % rhs
        }
        guard !result.overflow else { throw .overflow }
        return result.partialValue
    }
}

private enum StackOperator {
    case openParen
    case negate
    case binary(BinaryOperator)

    /// Whether this stacked operator must be applied before pushing `incoming`.
    func reducesBefore(_ incoming: BinaryOperator) -> Bool {
        switch self {
        case .openParen: false
        case .negate: true
        case .binary(let pending): pending.precedence >= incoming.precedence
        }
    }
}

private struct Evaluator {
    private var values: [Int64] = []
    private var operators: [StackOperator] = []
    /// True when the next token must start an operand (number, '(' or unary '-').
    private var expectingOperand = true

    mutating func operand(_ value: Int64) throws(CalcError) {
        guard expectingOperand else { throw .syntax }
        values.append(value)
        expectingOperand = false
    }

    mutating func openParen() throws(CalcError) {
        guard expectingOperand else { throw .syntax }
        operators.append(.openParen)
    }

    mutating func closeParen() throws(CalcError) {
        guard !expectingOperand else { throw .syntax }
        while let top = operators.popLast() {
            if case .openParen = top { return }
            try apply(top)
        }
        throw .syntax
    }

    mutating func minus() throws(CalcError) {
        if expectingOperand {
            operators.append(.negate)
        } else {
            try binary(.subtract)
        }
    }

    mutating func binary(_ op: BinaryOperator) throws(CalcError) {
        guard !expectingOperand else { throw .syntax }
        // Left-associative: reduce everything of equal or higher precedence.
        // Unary negation binds tighter than any binary operator.
        while let top = operators.last, top.reducesBefore(op) {
            operators.removeLast()
            try apply(top)
        }
        operators.append(.binary(op))
        expectingOperand = true
    }

    mutating func finish() throws(CalcError) -> Int64 {
        guard !expectingOperand else { throw .syntax }
        while let top = operators.popLast() {
            if case .openParen = top { throw .syntax }
            try apply(top)
        }
        guard values.count == 1, let result = values.last else { throw .syntax }
        return result
    }

    private mutating func apply(_ op: StackOperator) throws(CalcError) {
        switch op {
        case .openParen:
            throw .syntax
        case .negate:
            guard let value = values.popLast() else { throw .syntax }
            let (negated, overflow) = Int64(0).subtractingReportingOverflow(value)
            guard !overflow else { throw .overflow }
            values.append(negated)
        case .binary(let binary):
            guard let rhs = values.popLast(), let lhs = values.popLast() else { throw .syntax }
            values.append(try binary.apply(lhs, rhs))
        }
    }
}
