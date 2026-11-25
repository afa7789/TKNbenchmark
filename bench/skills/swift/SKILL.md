---
name: swift
description: "Version-correct, idiomatic Swift for the installed toolchain (swift-driver version: 1.120.5 Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Swift code."
---

# Swift 6.1 (Apple Swift 6.1.2)

## Version facts
- `// swift-tools-version: 6.0`+ ⇒ **Swift 6 language mode**: data races are compile **errors**. Tools 5.x ⇒ Swift 5 mode.
- In 6.1: typed throws `throws(E)`, `count(where:)`, `withTaskGroup { }` without `of:`, `nonisolated` on types/extensions, trailing commas in argument/parameter lists, `sending`, `~Copyable`/`consuming`, `@TaskLocal`, regex literals, `Mutex`/`Atomic` (`import Synchronization`), `indices(where:)` → `RangeSet`, `package` access.
- **Not in 6.1 (6.2+) — don't write**: `InlineArray`, `Span`, `Task.immediate`, `nonisolated(nonsending)`, default MainActor isolation (`.defaultIsolation`, `-default-isolation`), raw identifiers `` func `a b`() ``, `weak let`, isolated conformances, Swift Testing exit tests. `@concurrent` parses but is unchecked and inert. Unknown `enableUpcomingFeature` names are silently ignored.
- Missing `any` is only a warning in 6.1; still write `any P` (prefer `some P`).
- `Mutex`, `Atomic`, `RangeSet` need macOS 15/iOS 18: set `platforms`, else "'Mutex' is only available in macOS 15.0 or newer".

## Package layout
`Sources/AppCore/` (all logic), `Sources/app/main.swift` (thin CLI), `Tests/AppCoreTests/`.
```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "App",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "app", targets: ["app"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "AppCore", swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .executableTarget(name: "app", dependencies: [
            "AppCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
```
- Language mode: `swiftLanguageModes: [.v6]` (package) / `.swiftLanguageMode(.v5)` (target). `swiftLanguageVersions` is deprecated.
- `@main` in a file named `main.swift` → "'main' attribute cannot be used in a module that contains top-level code". Single file via `swiftc`: add `-parse-as-library`.

## Commands
```sh
swift package init --type executable|library|tool --name X  # tests default to Swift Testing
swift build                      # debug
swift run -c release app args
swift test                       # --filter Regex, --skip, --parallel, --enable-code-coverage
swift test list
swift build -c release --show-bin-path
swift build -c release -Xswiftc -cross-module-optimization
swift build -c release --swift-sdk x86_64-swift-linux-musl   # static Linux (after `swift sdk install`)
swift format -i -r Sources Tests ; swift format lint -r Sources   # bundled swift-format
```
`--static-swift-stdlib` is Linux-only.

## Concurrency
- Shared mutable state: `actor`, `@MainActor`, or `final class: Sendable` holding `let m = Mutex(State())` + `m.withLock { $0... }`. No GCD/semaphores in new code.
- Non-public structs/enums of Sendable members are implicitly Sendable; mark public ones explicitly.
- Prefer structured concurrency: `async let`, `withTaskGroup`/`withThrowingTaskGroup`, `withDiscardingTaskGroup`. `Task {}` inherits actor isolation; `Task.detached` rarely right.
- Actor reentrancy: state may change across any `await`; re-check after it.
- Cancellation is cooperative: `try Task.checkCancellation()` / `Task.isCancelled` in loops; `Task.sleep(for: .milliseconds(50))` (not `nanoseconds:`).
- Bridge callbacks: `try await withCheckedThrowingContinuation { c in api { c.resume(with: $0) } }` — resume exactly once.
- Streams: `let (stream, cont) = AsyncStream.makeStream(of: Int.self)`.
- `@unchecked Sendable` / `nonisolated(unsafe)` only with a real lock behind it; `@preconcurrency import M` for unmigrated modules.
```swift
let total = await withTaskGroup { group in          // 6.1: result type inferred
    for i in 1...10 { group.addTask { i * i } }
    var sum = 0
    for await v in group { sum += v }
    return sum   // NOT `await group.reduce(0, +)`: "sending 'group' risks causing data races"
}
```

| Error | Fix |
|---|---|
| `var 'x' is not concurrency-safe because it is nonisolated global shared mutable state` (also `static var`) | `let`, `@MainActor`, actor, or `Mutex` |
| `let 'x' is not concurrency-safe because non-'Sendable' type` | make type Sendable or `@MainActor let` |
| `main actor-isolated property 'p' can not be referenced from a nonisolated context` | mark caller `@MainActor`, or `await` from async |
| `actor-isolated property 'n' can not be mutated from a nonisolated context` | add an actor method |
| `sending 'x' risks causing data races` / `sending value of non-Sendable type '() async -> ()'` | stop using `x` after handing it off, make it Sendable, or `sending` param |
| `non-sendable result type 'T' cannot be sent from actor-isolated context` | return a Sendable struct |
| `mutation of captured var 'n' in concurrently-executing code` | return values from tasks; accumulate after |
| `main actor-isolated instance method ... cannot be used to satisfy nonisolated requirement` | `@MainActor` protocol, or `nonisolated func` |
| `non-final class 'C' cannot conform to 'Sendable'` / `stored property ... is mutable` | `final` + `let`s, or actor |
| `expression is 'async' but is not marked with 'await'` (`task.value`) | `await` (`try await` if throwing) |

## Errors & typed throws
```swift
enum ParseError: Error { case empty, bad(String) }
func parse(_ s: String) throws(ParseError) -> Int {
    guard !s.isEmpty else { throw .empty }
    guard let n = Int(s) else { throw .bad(s) }
    return n
}
do { _ = try parse("") } catch { print(error) }   // error: ParseError, switch exhaustively
```
Typed throws only for closed, local error sets. `catch is CancellationError` for cancelled tasks.

## Swift Testing (`import Testing`)
```swift
@Suite struct ParserTests {
    @Test("parses", arguments: [("1", 1), ("42", 42)])
    func parses(input: String, expected: Int) throws {
        #expect(try parse(input) == expected)
    }
    @Test func rejectsEmpty() throws {
        let e = #expect(throws: ParseError.self) { try parse("") }   // 6.1 returns error
        let n = try #require(Int("5")); #expect(n == 5)
    }
    @Test func callback() async { await confirmation(expectedCount: 1) { ok in ok() } }
}
```
`init()` = setUp (fresh instance per test). Parallel by default; `.serialized` to opt out. Traits: `.disabled("why")`, `.enabled(if:)`, `.tags(.x)` with `extension Tag { @Tag static var x: Self }`, `.timeLimit(.minutes(1))`, `withKnownIssue {}`, `Issue.record("msg")`. Don't mix XCTest assertions in.

## Stdlib/Foundation idioms
- `xs.count(where:)`, `dict[k, default: 0] += 1`, `Dictionary(grouping:by:)`, `xs.sorted(using: KeyPathComparator(\.name))`.
- `if let x {}`; `let v = if c { a } else { b }`.
- Strings: no `s[0]` ("cannot subscript String with an Int") — use `prefix`, `firstIndex`, or `Array(s.utf8)` for O(1) bytes. `String(substring)` to store. Native `s.replacing("-", with: "+")`, `split(separator: "-")`, `ranges(of:)`, `s.firstMatch(of: /id=(\d+)/)?.1`.
- Foundation: `URL.temporaryDirectory.appending(path:)`, `Date.now`, `JSONEncoder/Decoder` + `Codable`, `x.formatted(.number.precision(.fractionLength(2)))` (locale-dependent; use `String(x)` for machine output),
- Linux portability: `#if canImport(FoundationEssentials) import FoundationEssentials #else import Foundation #endif`.

## Performance
- Benchmark only `-c release` (debug is 10–100× slower).
- Structs, `final class`, generics/`some` over `any` in hot loops, `reserveCapacity`.
- Bulk I/O: `FileHandle.standardInput.readDataToEndOfFile()` then parse bytes (`UInt8(ascii: "0")`); build output in one `String` and write once, not `print` per line.
- `&+`/`&*` only where wraparound is intended; plain `+` traps on overflow.
- "unable to type-check this expression in reasonable time": annotate types, split expression.
