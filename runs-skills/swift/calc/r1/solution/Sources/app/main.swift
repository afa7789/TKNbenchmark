import CalcCore

var output = ""
output.reserveCapacity(1 << 16)

while let line = readLine(strippingNewline: false) {
    var bytes = Array(line.utf8)
    if bytes.last == UInt8(ascii: "\n") { bytes.removeLast() }
    guard let result = Calculator.evaluateLine(bytes) else { continue }
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
