# Lessons

- Harness filters that drop "build output" dirs must be checked against real project layouts:
  `bin/` is output in .NET but source in dune/Go/Dart. Rule now: skip `bin/` only next to a *proj file.
- On macOS a freshly built binary's first launch can take seconds (system scan). Warm the binary up
  before any startup-deadline test.
- Never test a process-killing helper (killStragglers) on a broad dir like /tmp; use an isolated dir.
- Agents leave background servers and .NET build daemons holding the CLI's stdout; wait on the
  final event + kill stragglers by cwd, and disable MSBuild node reuse / shared compilation.
