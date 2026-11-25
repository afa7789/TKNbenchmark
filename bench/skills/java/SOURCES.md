# Sources

## Official documentation and release notes
- https://builds.shipilev.net/backports-monitor/release-notes-27.txt — Full JDK 27 release notes text: 9 JEPs, removed launcher flags (-noverify, -Xverify:none, -noclassgc), UseCompressedClassPointers obsolete, JVMCI removed, ThreadPoolExecutor.finalize removed, HttpServer path-prefix matching, AOTMode=required alias, short ISO offsets.
- https://builds.shipilev.net/backports-monitor/release-notes-26.txt — JDK 26 notes: Thread.stop removed, Comparator.min/max, UUID v7 (UUID.ofEpochMillis), Process implements Closeable, Duration.MIN/MAX, Instant.plusSaturating, HTTP/3, jdk.jsobject and jrunscript removed.
- https://builds.shipilev.net/backports-monitor/release-notes-25.txt — JDK 25 notes: Reader.readAllAsString/readAllLines, boxed-primitive constructor deprecation, 32-bit x86 removed, stdin.encoding.
- https://www.oracle.com/java/technologies/javase/27-relnote-issues.html — Oracle JDK 27 release notes index (fetch blocked; used via search snippets for removal list).
- https://openjdk.org/projects/jdk/27/ — JDK 27 JEP list and schedule (fetch blocked; JEP list confirmed via release notes text).
- https://openjdk.org/jeps/451 — Dynamic agent loading warnings (context for Mockito agent setup).

## Feature summaries of recent releases
- https://www.happycoders.eu/java/java-27-features/ — JDK 27 API deltas: LazyConstant (isInitialized/orElse removed, Set.ofLazy, error state), StructuredTaskScope (R_X type param, ExecutionException, timeout() rename, awaitAll removed), primitive patterns withdrawn.
- https://www.happycoders.eu/java/java-26-features/ — JDK 26 changes: final-field mutation warnings (JEP 500), Applet API removal, LazyConstant 2nd preview, structured concurrency 6th preview.
- https://www.infoq.com/news/2026/08/java-27-so-far/ — JDK 27 JEP categories, PEM API renames, JDK 28 outlook (JSON incubator, value objects).
- https://howtodoinjava.com/java/java-27-features/ — Cross-check of the 9 JDK 27 JEPs.
- https://www.azul.com/blog/jdk-27-the-quiet-before-the-storm/ — Cross-check: JDK 27 is a small non-LTS release; LTS remains 25.

## Style guide
- https://google.github.io/styleguide/javaguide.html — Naming, imports (no wildcard/module imports), one top-level class per file, @Override always, new-style switch, `///` Markdown Javadoc allowed, never swallow exceptions.

## Published agent rules / developer practice
- https://dev.to/machinecodingmaster/stop-correcting-your-ai-write-a-cursorrules-to-force-jdk-26-idioms-and-kill-legacy-java-26kf — Agents default to pre-17 Java; rules push records, pattern switch, `_`, virtual threads, ScopedValue.
- https://adambien.blog/roller/how_to_start_an_llm_assisted_java_project — Keep agent files to build commands; JDK libraries first; justify every dependency.
- https://kevinlin.github.io/ai-sdlc-playbook/ide-rules/languages/java — Common cursor-rule consensus: records, sealed types, pattern matching for modern Java.
- https://www.skills.sh/jabrena/cursor-rules-java/125-java-concurrency — Published Java agent skill set (concurrency: virtual threads, ScopedValue over ThreadLocal).
- https://blog.jetbrains.com/idea/2026/03/ai-assisted-java-application-development-with-agent-skills/ — Skills load on demand; keep them focused.
- https://dzone.com/articles/agents-md-java — Example AGENTS.md for a Java 25 project (build/test commands first).
- https://docs.openrewrite.org/recipes/java/migrate/addmockitojavaagenttomavensurefireplugin — Mockito must be added as -javaagent in Surefire on JDK 21+.
- https://groups.google.com/g/project-lombok/c/9Hi9k88u5q0 — Lombok support policy for new JDKs (reason to prefer records).

## Build and test tooling
- https://docs.junit.org/6.1.1/release-notes/ — JUnit 6 single version across platform/jupiter; 6.1.x current stable.
- https://repo1.maven.org/maven2/ (maven-metadata.xml for junit-bom, maven-compiler/surefire/jar/dependency plugins, mockito-core, lombok) — Latest stable versions used in SKILL.md.

## Verified locally (installed OpenJDK 27.0.1.1, Maven 3.10.2, Gradle 9.9.2)
- javap of java.lang.IO, LazyConstant, ScopedValue, StructuredTaskScope(+Joiner/Configuration), Gatherers, SequencedCollection, Comparator, Process, Reader, UUID, Duration, Instant, List/Map/Set.ofLazy.
- Compiled/ran every snippet and command in SKILL.md; captured exact compiler/runtime error messages.
