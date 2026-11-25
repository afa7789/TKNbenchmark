import CalcCore
import Testing

@Suite struct CalculatorTests {
    private func eval(_ s: String) -> Result<Int64, CalcError>? { Calculator.evaluateLine(s) }

    @Test(arguments: [
        ("1 + 2 * 3", Int64(7)), ("-7 / 2", -3), ("-7 % 3", -1), ("7 % -3", 1),
        ("--5", 5), ("-(2 + 3)", -5), ("10 - 4 - 3", 3), ("2*(3+4)*5", 70),
        ("(-9223372036854775807 - 1) % -1", 0), ("-9223372036854775807 - 1", .min),
        ("- 2 * 3", -6), ("100 / 10 / 5", 2),
    ])
    func values(input: String, expected: Int64) {
        #expect(eval(input) == .success(expected))
    }

    @Test(arguments: [
        ("(1 + 2", CalcError.syntax), ("1 +", .syntax), ("()", .syntax), ("1 2", .syntax),
        ("+1", .syntax), ("abc", .syntax), ("1)", .syntax), ("1 / 0", .divisionByZero),
        ("5 % 0", .divisionByZero), ("9223372036854775807 + 1", .overflow),
        ("9223372036854775808", .overflow), ("-9223372036854775808", .overflow),
        ("(-9223372036854775807 - 1) / -1", .overflow), ("-(-9223372036854775807 - 1)", .overflow),
    ])
    func errors(input: String, expected: CalcError) {
        #expect(eval(input) == .failure(expected))
    }

    @Test func blankLines() {
        #expect(eval("") == nil)
        #expect(eval(" \t ") == nil)
    }

    @Test func deepNesting() {
        let depth = 200_000
        let input = String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth)
        #expect(eval(input) == .success(1))
        #expect(eval(String(repeating: "-", count: depth + 1) + "1") == .success(-1))
    }
}
