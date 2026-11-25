import CalcCore

var output = ""
output.reserveCapacity(1 << 16)

// Keep the raw line: only "\n" terminates a line, so a stray "\r" is input
// (and therefore a syntax error), not part of the line ending.
while let rawLine = readLine(strippingNewline: false) {
    var line = Substring(rawLine)
    if line.utf8.last == UInt8(ascii: "\n") {
        line = Substring(line.utf8.dropLast())
    }
    guard let result = Calculator.evaluateLine(line) else { continue }
    switch result {
    case .success(let value): output += String(value)
    case .failure: output += "error"
    }
    output += "\n"
    if output.utf8.count >= 1 << 16 {
        print(output, terminator: "")
        output.removeAll(keepingCapacity: true)
    }
}
print(output, terminator: "")
