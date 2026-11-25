---
name: java
description: "Version-correct, idiomatic Java for the installed toolchain (openjdk version \"27.0.1.1\" 2026-11-17): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Java code."
---

# Java 27 (OpenJDK 27.0.1)

JDK 27 is a non-LTS release (Sept 2026). The current LTS is 25. Class files are major version 71. Compile with `--release 27`, or with the lowest release your users run.

## What exists and what doesn't
- **Final, use freely:** records, sealed types, pattern `switch` and record patterns, `_`, text blocks, `var`, virtual threads, sequenced collections, gatherers, `ScopedValue`, `import module`, compact source files, statements before `super(...)`, FFM (`java.lang.foreign`), `///` Markdown Javadoc.
- **Preview** (`--enable-preview` at compile AND run time; keep out of libraries): `StructuredTaskScope`, `LazyConstant` and `List|Map|Set.ofLazy`, PEM API. Primitive patterns (`case int i`) were withdrawn, so don't use them. Vector API is an incubator: `--add-modules jdk.incubator.vector`.
- **Gone, never emit:** string templates (`STR."\{x}"`), `Thread.stop/suspend/resume`, `java.applet`, Security Manager, `new Integer(..)` (use `valueOf`). Launcher flags `-noverify`, `-Xverify:none` and `-noclassgc` now fail. JVMCI and `-XX:+UseGraalJIT` are removed. `UseCompressedClassPointers` is ignored.
- **Defaults:** G1 is the GC everywhere, compact object headers are on, and the initial heap is small (set `-Xms` if needed). `HttpServer` contexts match by path prefix, so `/foo` doesn't match `/foobar`.

## Verified modern API
```java
xs.getFirst(); xs.getLast(); xs.reversed();      // List, Deque, LinkedHashSet/Map
linkedMap.putFirst("a", 1); linkedMap.firstEntry();
Stream.of(1,2,3,4,5).gather(Gatherers.windowFixed(2)).toList(); // [[1,2],[3,4],[5]]
Stream.of(1,2,3).gather(Gatherers.scan(() -> 0, Integer::sum)).toList(); // [1,3,6]
urls.stream().gather(Gatherers.mapConcurrent(16, this::fetch)).toList(); // bounded, ordered
cmp.max(a, b); cmp.min(a, b);                    // Comparator defaults (26+)
UUID.ofEpochMillis(System.currentTimeMillis());  // UUIDv7
Math.clamp(v, 0, 10); sb.repeat("ab", 3); s.splitWithDelimiters("[,;]", 0);
reader.readAllAsString(); reader.readAllLines();
Duration.MAX; instant.plusSaturating(d); Thread.sleep(Duration.ofMillis(10));
try (Process p = pb.start()) { … }               // Closeable (26+)
try (HttpClient c = HttpClient.newHttpClient()) { … } // Version.HTTP_3 available
```
`Stream.toList()` returns an unmodifiable list. Use `Collectors.toCollection(ArrayList::new)` when the result must stay mutable.

## Language idioms
```java
sealed interface Shape permits Circle, Square {}
record Circle(double r) implements Shape {
    Circle { if (r < 0) throw new IllegalArgumentException("r < 0: " + r); }
}
record Square(double side) implements Shape {}
static double area(Shape s) {
    return switch (s) {         // no default: a new subtype becomes a compile error
        case Circle(var r) -> Math.PI * r * r;
        case Square(double side) -> side * side;
    };
}
return switch (o) {
    case null -> "null";
    case Integer i when i > 10 -> "big";   // guarded before unguarded
    case Integer i -> "int";
    default -> "other";
};
if (o instanceof Point(int x, _)) { … }
catch (NumberFormatException _) { … }
Child(String s) { int n = Integer.parseInt(s); super(n); } // validate before super
```

## Scripts
```java
// Hello.java  → java Hello.java   (no class; java.base auto-imported)
void main() { IO.println("Hi " + IO.readln("Name: ")); }
```
`java Main.java` also compiles the sibling `.java` files on demand. Preview code runs with `java --enable-preview Main.java`. Production code follows Google style: no wildcard or module imports, and one top-level type per file.

## Concurrency
- Use `try (var ex = Executors.newVirtualThreadPerTaskExecutor()) {…}`, where `close()` waits for all tasks. Never pool virtual threads. Bound concurrency with a `Semaphore` or `mapConcurrent`. `synchronized` no longer pins carriers (24+), so keep it.
- Use `ScopedValue` instead of `ThreadLocal` for context: `static final ScopedValue<User> USER = ScopedValue.newInstance();` then `ScopedValue.where(USER, u).run(() -> …)`, or `.call(() -> …)` for a result. Read it with `USER.get()`.
- `StructuredTaskScope` (preview) changes API in every release. In 27, `ShutdownOnFailure`, `Joiner.onTimeout`, `awaitAll` and `anySuccessfulResultOrThrow` don't exist:
```java
try (var scope = StructuredTaskScope.open(Joiner.<String>allSuccessfulOrThrow(),
        cf -> cf.withTimeout(Duration.ofSeconds(2)))) {
    scope.fork(() -> a()); scope.fork(() -> b());
    List<String> r = scope.join(); // ExecutionException, cause = first failure
}   // plain open(): join() returns null; read Subtask.get()
```
- `LazyConstant` (preview): `LazyConstant.of(this::load)`, read with `.get()`. It has no `isInitialized` or `orElse`. If the supplier throws or returns null, every later `get()` throws `NoSuchElementException` and the supplier is never retried.

## Build
Maven:
```xml
<properties><maven.compiler.release>27</maven.compiler.release>
  <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding></properties>
<!-- import org.junit:junit-bom:6.1.3 (pom, import); test dep org.junit.jupiter:junit-jupiter.
 maven-compiler-plugin 3.15.0, surefire 3.6.1, jar 3.5.1 (archive/manifest/mainClass) -->
```
Commands: `mvn -B verify`, `mvn test -Dtest='FooTest#bar'`, and `mvn wrapper:wrapper` once, then `./mvnw`. Layout: `src/main/java/com/acme/app/…` and `src/test/java/…`, with tests named `*Test`.

Gradle 9.9: `gradle init --type java-application --dsl kotlin --test-framework junit-jupiter --java-version 27 --use-defaults`. Configure `java { toolchain { languageVersion = JavaLanguageVersion.of(27) } }` and `testRuntimeOnly("org.junit.platform:junit-platform-launcher")`. Run `./gradlew build` and `./gradlew test --tests 'com.acme.FooTest'`.

Mockito 5 (fixes `self-attaching` warning): add the `maven-dependency-plugin` goal `properties` plus the surefire `<argLine>-javaagent:${org.mockito:mockito-core:jar}</argLine>`. Use `@{argLine}` only when JaCoCo sets it. Otherwise the fork dies with ``could not open `{argLine}'``.

Annotation processors (Lombok, MapStruct) don't run from the classpath. Declare them in `<annotationProcessorPaths>` or Gradle `annotationProcessor(...)`, or pass `-processorpath`/`-proc:full`. Prefer records over Lombok.

## Ship
- `jar --create --file app.jar --main-class com.acme.Main -C classes .`
- Small runtime: `jlink --add-modules $(jdeps --print-module-deps --ignore-missing-deps app.jar) --strip-debug --no-header-files --no-man-pages --output rt`
- AOT cache for startup: train with `java -XX:AOTCacheOutput=app.aot -jar app.jar`, then run `java -XX:AOTCache=app.aot -jar app.jar`. Add `-XX:AOTMode=required` to fail fast if the cache can't be used.

## Errors → fixes
| Message | Fix |
|---|---|
| `--enable-preview must be used with either -source or --release` | `javac --release 27 --enable-preview` |
| `Preview features are not enabled … (class file version 71.65535)` | `java --enable-preview` (and in surefire argLine) |
| `compiled by a more recent version … (class file version 71.0)` | run on 27 or lower `--release` |
| `the switch expression does not cover all possible input values` | add the missing sealed subtype case |
| `this case label is dominated by a preceding case label` | put specific or guarded cases first |
| `reference to List is ambiguous` (two `import module`) | `import java.util.List;` |
| `illegal escape character` at `\{` | no string templates; use `"%s".formatted(x)` |
| `println … cannot be applied` / `ambiguous` around a generic `collect(...)` | assign to a typed local first |
| `Final field … mutated reflectively` | stop it (stopgap: `--enable-final-field-mutation=ALL-UNNAMED`) |
| `sun.misc.Unsafe::… will be removed` | `VarHandle` / `MemorySegment`; upgrade the library |
| `restricted method … System::loadLibrary` | `--enable-native-access=ALL-UNNAMED` or manifest `Enable-Native-Access: ALL-UNNAMED` |
