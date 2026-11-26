# Lessons

- Harness filters that drop "build output" dirs must be checked against real project layouts:
  `bin/` is output in .NET but source in dune/Go/Dart. Rule now: skip `bin/` only next to a *proj file.
- On macOS a freshly built binary's first launch can take seconds (system scan). Warm the binary up
  before any startup-deadline test.
- Never test a process-killing helper (killStragglers) on a broad dir like /tmp; use an isolated dir.
- Prove what an agent's context holds by observation (a canary word it must repeat), never by reading
  flags: CLAUDE.md loads under `$TMPDIR/tknbench` but not in the Claude Code session scratchpad, and
  bundled skills survive `--tools` lists. A non-base arm must also match the baseline's toolchains.
- Path ownership checks compare whole components (`p + '/'` startsWith `root + '/'`): a bare prefix let
  the C skill writer's cleanup kill the C++ writer (`skillgen/c` ⊂ `skillgen/cpp`).
- JVM tools resolve `~` from the `user.home` property, not `$HOME`: a sandboxed HOME does not isolate the
  Clojure CLI's Maven repo (`CLJ_JVM_OPTS=-Duser.home=…` does). Check every new toolchain's cold build
  reports a non-zero cache in the sandbox before trusting its disk numbers.
- A gate test must use input that cannot pass the gate: testing "missing skill" with a language whose skill
  had just been written ran a real benchmark case.
- Never compare performance measured in different sessions, or in one block per arm: the same binaries ran
  30% slower in macOS Low Power Mode and drifted again mid-session in High Power. Measure arms paired and
  interleaved per case (`perf.mjs --paired`), and re-time a few reference binaries before trusting a session.
- Go makes its module cache read-only: a sandbox where Go downloaded modules cannot be removed with a plain
  recursive remove. Build with GOFLAGS=-modcacherw and remove trees with lib's removeTree.
- Agents leave background servers and .NET build daemons holding the CLI's stdout; wait on the
  final event + kill stragglers by cwd, and disable MSBuild node reuse / shared compilation.
