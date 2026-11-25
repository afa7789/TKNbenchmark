import CalcCore
import Testing

@Suite struct CalculatorTests {
    @Test(arguments: [
        ("1 + 2 * 3", 7), ("-7 / 2", -3), ("-7 % 3", -1), ("7 % -3", 1),
        ("10 - 4 - 3", 3), ("--5", 5), ("2 * -3", -6), ("-(2 + 3)", -5),
        ("9223372036854775807", Int64.max), ("-9223372036854775807 - 1", Int64.min),
        ("(-9223372036854775807 - 1) % -1", 0), ("\t( ( 4 ) )\t", 4),
    ] as [(String, Int64)])
    func evaluates(input: String, expected: Int64) {
        #expect(Calculator.evaluate(input) == .success(expected))
    }

    @Test(arguments: [
        ("(1 + 2", CalcError.syntax), ("1 +", .syntax), ("()", .syntax), ("1 2", .syntax),
        ("+1", .syntax), ("abc", .syntax), ("1)", .syntax), ("1 / 0", .divisionByZero),
        ("5 % 0", .divisionByZero), ("9223372036854775808", .overflow),
        ("9223372036854775807 + 1", .overflow), ("-(-9223372036854775807 - 1)", .overflow),
        ("(-9223372036854775807 - 1) / -1", .overflow), ("3037000500 * 3037000500", .overflow),
    ])
    func fails(input: String, expected: CalcError) {
        #expect(Calculator.evaluate(input) == .failure(expected))
    }

    @Test func deepNesting() {
        let depth = 200_000
        let input = String(repeating: "(", count: depth) + "-1" + String(repeating: ")", count: depth)
        #expect(Calculator.evaluate(input) == .success(-1))
    }
}
