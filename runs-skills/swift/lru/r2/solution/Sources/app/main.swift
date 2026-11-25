import AppCore

/// Buffers output and writes it in large chunks rather than per line.
struct OutputBuffer {
    private var buffer = ""
    private let flushThreshold = 1 << 16

    init() { buffer.reserveCapacity(flushThreshold + 128) }

    mutating func writeLine(_ line: String) {
        buffer += line
        buffer += "\n"
        if buffer.utf8.count >= flushThreshold { flush() }
    }

    mutating func flush() {
        guard !buffer.isEmpty else { return }
        print(buffer, terminator: "")
        buffer.removeAll(keepingCapacity: true)
    }
}

func run() {
    guard let header = readLine(),
          let capacity = Int(normalizedLine(header).filter { $0 != " " }),
          capacity > 0
    else { return }

    var processor = CommandProcessor(capacity: capacity)
    var output = OutputBuffer()

    while let line = readLine() {
        guard let command = Command(line: normalizedLine(line)) else { continue }
        if let result = processor.execute(command) {
            output.writeLine(result)
        }
    }
    output.flush()
}

run()
