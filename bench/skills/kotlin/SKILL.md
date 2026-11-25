---
name: kotlin
description: "Version-correct, idiomatic Kotlin for the installed toolchain (info: kotlinc-jvm 2.4.21 (JRE 27.0.1.1)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Kotlin code."
---

# Kotlin 2.4 (JVM)

kotlinc 2.4.21 (K2 only), Gradle 9.x, JDK 27. Snippets verified on this toolchain.

## Toolchain facts that break builds
- Max `-jvm-target` is **26** (CLI default 1.8). On JDK 27 Gradle fails: `Inconsistent JVM-target compatibility detected for tasks 'compileJava' (27) and 'compileKotlin' (26)`. Fix: `kotlin { jvmToolchain(21) }` (foojay downloads the JDK) or pin both targets (below).
- The runner is now **`kotlinr`**. `kotlin` is a deprecated alias.
- The coroutines jar in the compiler's `lib/` is 1.8.0. Declare 1.11.0.

## CLI
```sh
kotlinc Main.kt -include-runtime -d app.jar && java -jar app.jar  # Main-Class = MainKt
kotlinr script.main.kts a b     # @file:DependsOn("group:artifact:ver") at top; args = arguments
```
With `@file:JvmName("App")` the jar's Main-Class is still `MainKt` (fails). Run `java -cp app.jar App`.

## Gradle project (verified: `./gradlew build run`)
Layout: `src/main/kotlin/<pkg>/`, `src/test/kotlin/<pkg>/`. Multi-module: versions in `gradle/libs.versions.toml`.
```kotlin
// settings.gradle.kts
plugins { id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0" }
rootProject.name = "demo"
```
```kotlin
// build.gradle.kts
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
plugins {
    kotlin("jvm") version "2.4.21"
    kotlin("plugin.serialization") version "2.4.21"
    application
}
repositories { mavenCentral() }
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
java { targetCompatibility = JavaVersion.VERSION_21 } // or: kotlin { jvmToolchain(21) }
kotlin {
    // explicitApi()  // for libraries
    compilerOptions {
        jvmTarget = JvmTarget.JVM_21
        freeCompilerArgs.addAll("-Xjdk-release=21", "-Xreturn-value-checker=check")
    }
}
application { mainClass = "demo.MainKt" }
tasks.test { useJUnitPlatform() } // else kotlin("test") picks JUnit 4
```
- `kotlinOptions {}` is an error. Use `compilerOptions {}`.
- `./gradlew build`, `test --tests 'demo.MainTest.parseFails'`, `run --args="a b"`, `installDist` (writes `build/install/demo/bin/demo`), `distZip`.

## Language features stable in 2.4 (no flags)
`-Xcontext-parameters`/`-Xexplicit-backing-fields` now just warn "redundant".
```kotlin
context(log: Logger)                 // context parameters; `_: Logger` if unused by name
fun save(id: Int) { log.info("save $id") }
with(Logger()) { save(1) }           // or context(Logger()) { save(2) }

class Repo {                         // explicit backing field: replaces `private val _x` + getter
    val items: List<String>
        field = mutableListOf()
    fun add(s: String) { items.add(s) }  // smart-cast to MutableList inside the class
}

fun area(s: Shape): Double = when (s) {  // guard conditions
    is Circle if s.r < 0 -> error("negative radius")
    is Circle -> Math.PI * s.r * s.r
    is Rect -> s.w * s.h
    Empty -> 0.0                     // data object; exhaustive, no else
}
val tpl = $$"""{"price": "$${total}$"}"""  // multi-dollar interpolation: lone $ is literal
for (x in xs) { ys.forEach { if (it == x) continue } }  // non-local break/continue in inline lambdas
```
Also stable: nested type aliases, data-flow `when` exhaustiveness.
- **Removed**: context receivers (`context(Logger)` with no name). Write `context(log: Logger)`.
- **Still experimental** (need flags; avoid): collection literals `[1, 2]` (error `array literals outside of annotations are unsupported`; use `listOf`), name-based destructuring, explicit context arguments.

## Standard library, current API
```kotlin
import kotlin.time.Clock; import kotlin.time.Instant   // NOT kotlinx.datetime (removed 0.7)
import kotlin.uuid.Uuid                                  // stable
val now = Clock.System.now(); Instant.parse("2026-01-01T00:00:00Z").toEpochMilliseconds()
Uuid.random(); Uuid.parse(s); Uuid.parseOrNull(s)  // generateV7() needs ExperimentalUuidApi
xs.isSorted(); xs.isSortedBy { it.k }                  // stable in 2.4
Base64.Default.encode(bytes)                            // kotlin.io.encoding.Base64; also UrlSafe, Mime, Pem
255.toHexString()                     // "000000ff" (full width!)
255.toHexString(HexFormat { number.removeLeadingZeros = true })  // "ff"; or 255.toString(16)
readln(); readlnOrNull()              // readLine() is deprecated
val (v, d) = measureTimedValue { work() }               // kotlin.time
(dir / "a.txt").writeText("x"); path.useLines { it.count() }; dir.walk()  // kotlin.io.path.*
```
- Opt-in required (`@OptIn(ExperimentalStdlibApi::class)`): `allDistinct()`, `allEqual()`, `getOrPutIfNull`, `getOrPutIfMissing`, `Map.Entry.copy()`.
- `kotlin.concurrent.atomics.AtomicInt` needs `ExperimentalAtomicApi`; `java.util.concurrent.atomic` doesn't.
- kotlin.test `assertTrue(c) { "…" }` needs `ExperimentalKotlinTestApi`; use `assertTrue(c, "msg")`.

## Coroutines (1.11.0)
```kotlin
suspend fun loadAll(ids: List<Int>): List<Int> = coroutineScope {
    ids.map { async { fetch(it) } }.awaitAll()
}
withContext(Dispatchers.IO) { blockingCall() }
val db = Dispatchers.IO.limitedParallelism(4)  // bounded view
Executors.newVirtualThreadPerTaskExecutor().asCoroutineDispatcher().use { vt -> /* withContext(vt) */ }
@Test fun t() = runTest { assertEquals(listOf(2), loadAll(listOf(1))) }  // delays are virtual
```
- `runCatching { suspendCall() }` **swallows `CancellationException`**; the coroutine keeps running after cancel. Catch specific exceptions or rethrow it; call `currentCoroutineContext().ensureActive()` in long loops.
- No `GlobalScope`; no `Job()` passed to `launch`/`async`. `runBlocking` only in `main`, never in suspend code or tests.

## kotlinx.serialization (1.11.0)
```kotlin
@Serializable data class User(val id: Uuid, @SerialName("created_at") val at: Instant, val tags: List<String> = emptyList())
val json = Json { ignoreUnknownKeys = true }   // reuse one instance
json.encodeToString(u); json.decodeFromString<User>(s)
```
`Uuid`/`Instant` need no custom serializer. `Serializer for class 'X' is not found` = missing `@Serializable` or plugin. `Encountered an unknown key` = set `ignoreUnknownKeys`.

## Unused-result checker
`-Xreturn-value-checker=check` warns `unused return value of 'sorted'` (bug: `list.sorted()` not assigned). Discard deliberately with `val _ = f()`; mark own functions `@IgnorableReturnValue`.

## Compiler errors → fix
| Message | Fix |
|---|---|
| `smart cast to 'String' is impossible, because 'x' is a mutable property…` | `val n = x ?: return` / `x?.let { }` |
| `'when' expression must be exhaustive. Add the 'is S2' branch…` | add the branch (avoid `else` on sealed types) |
| `suspend function … can only be called from a coroutine…` | make the caller `suspend`, or `runBlocking` in `main` |
| `only safe (?.) or non-null asserted (!!.) calls are allowed…` | `?.`, `?:`, `requireNotNull(x)`; avoid `!!` |
| `this declaration needs opt-in…` | `@OptIn(X::class)` or `-opt-in=fq.X` |
| `platform declaration clash: … same JVM signature` | `@JvmName("fooStrings")` on one overload |
| `unresolved reference 'add' on receiver of type 'List<Int>'` | declare `MutableList`; expose `List` |

## Idioms (correct and fast)
- Closed states: `sealed interface` + `data class`/`data object`, `when` without `else`. IDs: `@JvmInline value class Id(val v: Long)`.
- `Enum.entries` not `values()`; `0..<n`; `buildList {}`; `map.getOrPut(k) { mutableListOf() } += v`; `groupingBy { }.eachCount()`.
- `require()` args, `check()` state, `error()` unreachable; `use {}` closes resources; `asSequence()` only for big chains.
- Return read-only `List`/`Map` from public API. Prefer default arguments to overloads and top-level functions to `object Utils`.
- Style: 4-space indent, trailing commas, file named after its class, directories mirror packages.
