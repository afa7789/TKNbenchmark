# Sources

## Official documentation and release notes
- https://www.swift.org/blog/swift-6.1-released — 6.1 features: `nonisolated` types/extensions, TaskGroup result inference, trailing commas, package traits, Swift Testing `TestScoping` and `#expect(throws:)` returning the error.
- https://raw.githubusercontent.com/swiftlang/swift/main/CHANGELOG.md — 6.0/6.1 SE list (typed throws, `sending`, region isolation, `@TaskLocal` macro, `RangeSet`, ExistentialAny downgraded to warning) and the 6.2+ features that 6.1 lacks.
- https://raw.githubusercontent.com/swiftlang/swift-migration-guide/main/Guide.docc/CommonProblems.md — Swift 6 concurrency diagnostics and the fixes the guide recommends (global state, protocol isolation mismatch, sending, `@preconcurrency`).
- https://raw.githubusercontent.com/swiftlang/swift-package-manager/release/6.1/Sources/Workspace/InitPackage.swift — what `swift package init` generates per `--type`, and that Swift Testing is the default.
- https://www.swift.org/documentation/articles/static-linux-getting-started.html — `swift sdk install` and `--swift-sdk x86_64-swift-linux-musl` for static Linux binaries.
- https://www.swift.org/documentation/server/guides/building.html — `-c release`, `--show-bin-path`, `-Xswiftc -cross-module-optimization`.
- https://developer.apple.com/documentation/testing/migratingfromxctest — XCTest → Swift Testing mapping (`#expect`/`#require`, `confirmation`, traits, parallel by default). The page didn't render, so every API taken from it was compiled and checked locally.

## Style guides
- https://www.swift.org/documentation/api-design-guidelines/ — official naming and argument-label conventions (taken as assumed knowledge, not repeated).
- https://google.github.io/swift/ — widely followed style rules: no force-unwrap/`try!` outside tests, trapping arithmetic by default, `guard` for early exit.

## Published agent skills / AGENTS.md
- https://raw.githubusercontent.com/twostraws/Swift-Concurrency-Agent-Skill/main/swift-concurrency-pro/SKILL.md — common agent mistakes: actor reentrancy, unneeded `Task.detached`, `@unchecked Sendable` used to silence errors, ignoring cancellation, GCD in new code.
- https://cdn.jsdelivr.net/gh/twostraws/SwiftUI-Agent-Skill@main/swiftui-pro/references/swift.md — modern API preferences: `replacing(_:with:)`, `count(where:)`, `Task.sleep(for:)`, `Date.now`, FormatStyle over `String(format:)`, `if let x` shorthand.
- https://cdn.jsdelivr.net/gh/twostraws/SwiftAgents@main/AGENTS.md — AGENTS.md baseline: strict concurrency, prefer async APIs, no GCD, avoid force unwraps.
- https://skills.sh/nonameplum/agent-skills/swift-package-manager, https://github.com/MFranceschi6/swift-xml-coder/blob/main/AGENTS.md, https://github.com/gaelic-ghost/SwiftASB/blob/main/AGENTS.md (seen as search snippets) — consensus that `swift build` and `swift test` are the validation loop, plus coverage and lint steps.

## Local verification (installed toolchain, Apple Swift 6.1.2)
- `/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface` — checked manifest API (`swiftLanguageModes`, `swiftLanguageMode(_:)`, `enableUpcomingFeature`, traits, platform versions, no `defaultIsolation`). A sample Package.swift typechecked against it.
- `swiftc -swift-version 6` with the MacOSX15.5 SDK — compiled and ran every code example and recorded the exact diagnostic texts. Confirmed which 6.2 features are missing (`InlineArray`, `Span`, `Task.immediate`, `nonisolated(nonsending)`, `weak let`, raw identifiers, `-default-isolation`). Found that `await group.reduce` fails in a TaskGroup closure.
- Testing.framework in CommandLineTools — built and ran a Swift Testing suite.
- `swift format` (bundled) — checked the `format -i -r` and `lint` subcommands. Checked SwiftPM option names via `strings` on the swift-package binary, because that binary fails to load locally (llbuild symbol mismatch).
