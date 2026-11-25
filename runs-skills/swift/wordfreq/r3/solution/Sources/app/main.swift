#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import WordFreqCore

/// Streams standard input through `counter` in fixed-size chunks.
func consumeStandardInput(into counter: inout WordCounter) {
    let chunkSize = 1 << 20
    let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: chunkSize)
    defer { buffer.deallocate() }

    while true {
        let bytesRead = read(STDIN_FILENO, buffer.baseAddress, chunkSize)
        if bytesRead > 0 {
            counter.consume(UnsafeBufferPointer(rebasing: buffer[..<bytesRead]))
        } else if bytesRead == 0 || errno != EINTR {
            break
        }
    }
    counter.finish()
}

var counter = WordCounter()
consumeStandardInput(into: &counter)
print(counter.mostFrequent(10).formattedReport(), terminator: "")
