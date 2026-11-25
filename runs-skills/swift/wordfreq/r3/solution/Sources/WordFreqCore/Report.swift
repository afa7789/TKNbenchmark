extension [WordCount] {
    /// Renders one `<count> <word>` line per entry, each terminated by a newline.
    public func formattedReport() -> String {
        var output = ""
        for entry in self {
            output += "\(entry.count) \(entry.word)\n"
        }
        return output
    }
}
