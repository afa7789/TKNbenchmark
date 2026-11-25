import CalcCore

/// Reads one expression per line from standard input and prints each result.
var output = ""
output.reserveCapacity(1 << 16)

while var line = readLine(strippingNewline: false) {
    let result = line.withUTF8 { bytes -> String? in
        // Lines are terminated by "\n" only; any other byte belongs to the expression.
        let body = bytes.last == UInt8(ascii: "\n") ? UnsafeBufferPointer(rebasing: bytes.dropLast()) : bytes
        guard !Calculator.isBlank(body) else { return nil }
        switch Calculator.evaluate(body) {
        case .success(let value): return String(value)
        case .failure: return "error"
        }
    }
    if let result {
        output += result
        output += "\n"
    }
    if output.utf8.count >= 1 << 16 {
        print(output, terminator: "")
        output.removeAll(keepingCapacity: true)
    }
}
print(output, terminator: "")
