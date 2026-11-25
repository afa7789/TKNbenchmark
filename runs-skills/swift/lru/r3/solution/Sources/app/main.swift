import LRUCore

/// Reads commands from standard input and writes their results to standard output.
func run() {
    guard let header = readLine(), let capacity = CommandProcessor.parseCapacity(header) else {
        return
    }

    var processor = CommandProcessor(capacity: capacity)
    let flushThreshold = 1 << 16
    var output = ""
    output.reserveCapacity(flushThreshold + 128)

    while let line = readLine() {
        var command = Substring(line)
        while command.last == "\r" { command.removeLast() }
        guard let result = processor.execute(command) else { continue }
        output += result
        output += "\n"
        if output.utf8.count >= flushThreshold {
            print(output, terminator: "")
            output.removeAll(keepingCapacity: true)
        }
    }
    print(output, terminator: "")
}

run()
