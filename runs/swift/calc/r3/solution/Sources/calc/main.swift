var evaluator = Evaluator()
var output = ""
output.reserveCapacity(1 << 16)

while let line = readLine(strippingNewline: true) {
    do {
        if let value = try evaluator.evaluate(line.utf8) {
            output += String(value)
            output += "\n"
        }
    } catch {
        output += "error\n"
    }
    if output.utf8.count >= 1 << 16 {
        print(output, terminator: "")
        output.removeAll(keepingCapacity: true)
    }
}
print(output, terminator: "")
