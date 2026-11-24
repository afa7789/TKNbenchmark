/// Reads one expression per line from standard input and prints its value,
/// or `error` if it cannot be evaluated. Blank lines produce no output.

var evaluator = Evaluator()
var output = ""
output.reserveCapacity(1 << 16)

func isBlank(_ line: String.UTF8View) -> Bool {
    line.allSatisfy { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
}

while let line = readLine(strippingNewline: true) {
    let bytes = line.utf8
    if isBlank(bytes) { continue }

    do {
        output += String(try evaluator.evaluate(bytes))
    } catch {
        output += "error"
    }
    output += "\n"

    if output.utf8.count >= 1 << 16 {
        print(output, terminator: "")
        output.removeAll(keepingCapacity: true)
    }
}
print(output, terminator: "")
