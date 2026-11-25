# Sources

## Official documentation and release notes
- https://kotlinlang.org/docs/whatsnew24.html — 2.4.0 changes: context parameters, explicit backing fields and Uuid now stable; `isSorted*` and `getOrPutIfNull`/`IfMissing`; experimental flags (collection literals, explicit context args); Java 26 bytecode; K1 removed.
- https://kotlinlang.org/docs/whatsnew2420.html — 2.4.20: `kotlinr` replaces the `kotlin` runner; `allDistinct`/`allEqual` (ExperimentalStdlibApi); kotlin.test lazy messages (ExperimentalKotlinTestApi); Gradle 9.7 support.
- https://kotlinlang.org/docs/compatibility-guide-24.html — 2.4 breaking changes: `readLine()` deprecated, array literals outside annotations are an error, default annotation use-site targets changed.
- https://kotlinlang.org/docs/whatsnew23.html — 2.3: unused-return-value checker (`-Xreturn-value-checker`, `@IgnorableReturnValue`, `val _ =`), `kotlin.time.Instant`/`Clock` stable, Uuid parse/generate APIs.
- https://kotlinlang.org/docs/whatsnew2320.html — 2.3.20: context receivers removed, name-based destructuring flag, `Map.Entry.copy()`.
- https://kotlinlang.org/docs/whatsnew22.html — 2.2: guard conditions, non-local break/continue, multi-dollar interpolation now stable; `kotlinOptions` is an error; `-jvm-default`; Base64/HexFormat stable.
- https://kotlinlang.org/docs/gradle-configure-project.html — KGP 2.4.20–2.4.21 supports Gradle 7.6.3–9.7.0; `jvmToolchain`; foojay resolver; JVM-target validation; `kotlin("test")` defaults to JUnit 4 unless `useJUnitPlatform()` is set.
- https://kotlinlang.org/docs/coding-conventions.html — official style: file naming, directory and package layout, trailing commas, read-only collections, `entries`, `0..<n`, default arguments over overloads.
- https://raw.githubusercontent.com/Kotlin/kotlinx.coroutines/master/CHANGES.md — coroutines 1.11.0 is current; deprecations, including the lint against passing a `Job` to builders.
- https://github.com/Kotlin/kotlinx-datetime/releases — kotlinx-datetime 0.7.0 removed its own `Instant`/`Clock` in favor of `kotlin.time`.
- https://central.sonatype.com/artifact/org.jetbrains.kotlinx/kotlinx-serialization-json — current version 1.11.0 (confirmed by resolving it in Gradle).
- https://plugins.gradle.org/plugin/org.gradle.toolchains.foojay-resolver-convention — foojay resolver 1.0.0 (also what `gradle init` 9.9.2 generates).

## Community agent rules and skills (consensus points)
- https://dev.to/olivia_craft/claudemd-for-kotlin-13-rules-that-make-ai-write-idiomatic-coroutine-safe-kotlin-code-16kn — CLAUDE.md rules: no `!!`, sealed interfaces with exhaustive `when`, `runTest` instead of `runBlocking`, no `GlobalScope`, read-only public collections, Kotlin DSL with pinned versions.
- https://cdn.jsdelivr.net/npm/@softspark/ai-toolkit@4.20.0/app/skills/kotlin-rules/SKILL.md — kotlin-rules skill: `require`/`checkNotNull`, `buildList`, `coroutineScope`+`async`, `withContext(Dispatchers.IO)`, kotlinx.serialization over Jackson.
- https://cdn.jsdelivr.net/npm/mcp-subagents-opencode@1.2.5/build/templates/overlays/coder-kotlin.mdx — agent overlay: prefer suspend functions over callbacks, never use `GlobalScope`.
- https://tessl.io/registry/jbaruch/kotlin-tutor/files/rules/coroutines-for-concurrency.md — rule that kotlinx-coroutines is the default for async work.

## Local verification (installed toolchain)
- `kotlinc -help` / `kotlinc -X` (2.4.21) — the max `-jvm-target` is 26 with a default of 1.8; `-Xjdk-release`, `-Xreturn-value-checker`, `-Xexplicit-api`, `-Xcollection-literals` exist; passing `-Xcontext-parameters` is reported as redundant.
- `gradle init --type kotlin-application` (Gradle 9.9.2) — the generated layout, foojay 1.0.0, and `useJUnitPlatform()`.
- Scratch Gradle project built, tested and run — reproduced the JDK 27 vs JVM 26 target mismatch error and its fix; coroutines and serialization 1.11.0, `installDist`, `--tests` filter.
- Scratch `kotlinc`/`kotlinr` snippets — confirmed every API, opt-in and error message quoted in SKILL.md (e.g. `255.toHexString()` == `"000000ff"`, `runCatching` swallowing cancellation, the `@file:JvmName` Main-Class pitfall).
