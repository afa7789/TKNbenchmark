# Sources

- https://go.dev/doc/go1.26 — Go 1.26 release notes: new(expr), self-referential generics, errors.AsType, slog.NewMultiHandler, bytes.Buffer.Peek, T.ArtifactDir, rewritten go fix, removed go tool doc, the 307 redirect and url.Parse changes, crypto rand changes, ReverseProxy.Director deprecation.
- https://go.dev/doc/go1.25 — Go 1.25 release notes: sync.WaitGroup.Go, testing/synctest GA, http.CrossOriginProtection, the nil-check compiler fix, container-aware GOMAXPROCS, go doc -http, jsonv2 experiment, vet waitgroup/hostport.
- https://go.dev/doc/go1.24 — Go 1.24 release notes: tool directives/go get -tool, testing.B.Loop, T.Context/T.Chdir, os.Root, strings/bytes Seq iterators, omitzero, crypto/rand.Text, vet printf non-constant format check.
- https://go.dev/doc/go1.23 — Go 1.23 release notes: range-over-func, iter package, slices/maps iterator functions, unbuffered/GC-able timers, go mod tidy -diff, go env -changed.
- https://go.dev/doc/go1.22 — Go 1.22 release notes: per-iteration loop variables, range over int, ServeMux method/wildcard patterns, math/rand/v2.
- https://go.dev/blog/gofix — go fix workflow (-diff, rerun until stable, per-GOOS runs) and the modernizer list.
- https://go.dev/blog/inliner — //go:fix inline directive syntax for funcs, consts, type aliases.
- https://go.dev/doc/modules/layout — official module layout (cmd/, internal/, root package).
- https://go.dev/doc/tutorial/govulncheck — govulncheck install/run commands.
- https://go.dev/wiki/CodeReviewComments — review rules: error strings, initialisms, receiver names, interfaces at consumer, contexts, useful test failures.
- https://google.github.io/styleguide/go/decisions — Google Go style decisions: naming, error handling, context first param, got/want test messages, t.Context in tests.
- https://cdn.jsdelivr.net/gh/jetbrains/go-modern-guidelines@main/README.md — JetBrains modern-Go agent skill: detect version from go.mod and use idioms up to that version.
- https://cdn.jsdelivr.net/gh/jetbrains/go-modern-guidelines@main/FEATURES.md — per-version idiom catalog (wg.Go, b.Loop, SplitSeq, slices.Sorted(maps.Keys), cmp.Or, OnceValue, WithTimeoutCause).
- https://raw.githubusercontent.com/Taiizor/agents-md-cookbook/790e0ba0d9c7fc9b96992bd68f08e9bfcb4c217e/templates/go/AGENTS.md — common AGENTS.md commands: go test -race, gofmt, golangci-lint, go mod tidy, table-driven tests.
- https://dev.to/olivia_craft/claudemd-for-go-13-rules-that-make-ai-write-idiomatic-production-safe-backend-code-2165 — consensus CLAUDE.md rules: goroutine exits/errgroup, ctx first, slog, govulncheck, handlers on a Server struct.
- https://golangci-lint.run/docs/configuration/file/ — golangci-lint v2 config format (considered; left out of SKILL.md for space since it is third-party).
- Local toolchain go1.26.4 (go doc, go tool fix help, GOROOT sources, scratch builds) — confirmed every API, signature, command, flag and error message quoted in SKILL.md.
