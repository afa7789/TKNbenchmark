/// calc: reads one expression per line from standard input and prints its
/// value, or `error`. Blank lines produce no output.

var evaluator = Evaluator()
var output = ""
output.reserveCapacity(1 << 16)

// Keep the terminator so that only `\n` ends a line; a stray `\r` is part of
// the expression (and therefore a syntax error).
while var line = readLine(strippingNewline: false) {
    line.withUTF8 { buffer in
        var bytes = buffer[...]
        if bytes.last == UInt8(ascii: "\n") {
            bytes.removeLast()
        }
        guard !Evaluator.isBlank(bytes) else { return }
        switch evaluator.evaluate(bytes) {
        case .success(let value):
            output += String(value)
        case .failure:
            output += "error"
        }
        output += "\n"
    }
    if output.utf8.count >= 1 << 16 {
        print(output, terminator: "")
        output.removeAll(keepingCapacity: true)
    }
}
print(output, terminator: "")
