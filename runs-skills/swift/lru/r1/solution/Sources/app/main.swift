import LRUCore

/// Lazily reads standard input line by line, stripping a trailing carriage return.
struct StandardInputLines: Sequence, IteratorProtocol {
    mutating func next() -> Substring? {
        guard var line = readLine(strippingNewline: true) else { return nil }
        if line.hasSuffix("\r") { line.removeLast() }
        return Substring(line)
    }
}

if let output = CommandProcessor.run(lines: StandardInputLines()) {
    print(output, terminator: "")
}
