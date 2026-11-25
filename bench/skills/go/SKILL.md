---
name: go
description: "Version-correct, idiomatic Go for the installed toolchain (go version go1.26.4 darwin/arm64): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Go code."
---

# Go 1.26 (go1.26.4)

## Version gating
- The `go` line in go.mod (the language version) decides which features compile. `go mod init` writes `go 1.26.4`. If the line is older, `new(5)` fails with `requires go1.26 or later (-lang was set to go1.24; check go.mod)`, and vet reports `errors.AsType requires go1.26 or later`. Raise it with `go get go@1.26`. Don't use APIs newer than the module's `go` line.
- Removed: `go tool doc`/`cmd/doc` (use `go doc pkg.Sym`). The old `go fix` rewrites are gone. `encoding/json/v2` still needs `GOEXPERIMENT=jsonv2`, so use `encoding/json` in normal code.

## New in 1.26 (verified)
```go
cfg := Config{Timeout: new(30 * time.Second), Debug: new(true)} // new(expr): no ptr helpers
if pe, ok := errors.AsType[*fs.PathError](err); ok { _ = pe.Path } // replaces var+errors.As
h := slog.NewMultiHandler(textH, jsonH)    // fan-out handler
p, err := buf.Peek(2)                      // bytes.Buffer, no advance
dir := t.ArtifactDir()                     // kept with `go test -artifacts`
```
- Generic types may reference themselves in constraints: `type Adder[A Adder[A]] interface{ Add(A) A }`. With `signal.NotifyContext`, `context.Cause(ctx)` names the signal.
- Behavior: `ServeMux` slash redirect is 307. `url.Parse` rejects `http://::1/`. crypto keygen ignores the `rand` arg (tests: `cryptotest.SetGlobalRandom`). `ReverseProxy.Director` is deprecated, use `Rewrite`.

## Modern idioms from 1.21–1.25 (prefer these)
```go
var wg sync.WaitGroup
for _, it := range items { wg.Go(func() { process(it) }) } // 1.25; no Add/Done; f must not panic
wg.Wait()
for i := range n {}                         // range over int; per-iteration loop vars (no x := x)
for part := range strings.SplitSeq(s, ",") {} // also FieldsSeq, Lines (keeps "\n"), bytes.*
keys := slices.Sorted(maps.Keys(m))         // maps.Keys/Values return iter.Seq, NOT slices
vals := slices.Collect(maps.Values(m))
for c := range slices.Chunk(xs, 100) {}
slices.SortFunc(us, func(a, b U) int { return cmp.Compare(a.Age, b.Age) }) // not sort.Slice
name := cmp.Or(os.Getenv("NAME"), "default") // first non-zero
before, after, ok := strings.Cut(kv, "=");  rest, ok := strings.CutPrefix(s, "Bearer ")
n := rand.N(10 * time.Second)               // math/rand/v2: IntN, N; never seed. Secrets: crypto/rand.Text()
min(a, b); max(x, y, z); clear(m)
get := sync.OnceValue(func() *Cfg { return load() })
ctx, cancel := context.WithTimeoutCause(ctx, d, errSlow); defer cancel()
At time.Time `json:"at,omitzero"`          // omitzero uses IsZero(); omitempty ignores structs/time
root, _ := os.OpenRoot(dir); data, err := root.ReadFile(name) // blocks ../ and symlink escape
```
Custom iterators:
```go
func Count(n int) iter.Seq[int] {
	return func(yield func(int) bool) {
		for i := range n { if !yield(i) { return } } // MUST stop when yield returns false
	}
}
```

## HTTP server (stdlib router since 1.22)
```go
mux := http.NewServeMux()
mux.HandleFunc("GET /items/{id}", func(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id") // "{path...}" = rest of path, "/{$}" = exact root only
})
srv := &http.Server{Addr: ":8080", Handler: http.NewCrossOriginProtection().Handler(mux),
	ReadHeaderTimeout: 5 * time.Second}
ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
defer stop()
go func() {
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) { log.Fatal(err) }
}()
<-ctx.Done()
sctx, cancel := context.WithTimeout(context.Background(), 10*time.Second); defer cancel()
_ = srv.Shutdown(sctx)
```
Clients: `&http.Client{Timeout: ...}` (the default client never times out). Always `defer resp.Body.Close()` and check `resp.StatusCode`. Limit bodies with `http.MaxBytesReader`. `dec.DisallowUnknownFields()` makes the decoder strict.

## Errors
- Wrap with `fmt.Errorf("load %q: %w", name, err)`: lowercase, no trailing period, no "failed to". `%v` hides the cause.
- Compare with `errors.Is(err, fs.ErrNotExist)`, never `==` on wrapped errors. Combine with `errors.Join`.
- Typed-nil trap: returning a nil `*MyErr` as `error` gives a non-nil error. Return a literal `nil`.
- Check `err` before you use any other result: since 1.25, `f.Name()` before the err check panics.

## Concurrency
- Every goroutine needs an exit (ctx, closed channel, WaitGroup). For fan-out with errors, use `golang.org/x/sync/errgroup`: `g, ctx := errgroup.WithContext(ctx); g.SetLimit(8); g.Go(func() error {...}); err := g.Wait()`.
- Don't copy structs that hold a `sync.Mutex` (vet: `assignment copies lock value`). Use pointer receivers on them.
- `time.Tick`/timers are GC'd when unreferenced (1.23+). Timer channels are unbuffered, so don't test `len(t.C)`.
- `context.Context` is the first param. Don't store it in structs. `context.Background()` only in main/tests (tests: `t.Context()`).

## Testing
```go
func TestSum(t *testing.T) {
	t.Parallel()
	for _, tt := range []struct{ name string; in []int; want int }{{"two", []int{1, 2}, 3}} {
		t.Run(tt.name, func(t *testing.T) {
			if got := Sum(tt.in...); got != tt.want { t.Errorf("Sum(%v) = %d, want %d", tt.in, got, tt.want) }
		})
	}
}
func TestWait(t *testing.T) { // fake clock: time.Sleep(time.Hour) returns instantly
	synctest.Test(t, func(t *testing.T) { /* goroutines + time; synctest.Wait() */ })
}
func BenchmarkSum(b *testing.B) { for b.Loop() { Sum(xs...) } } // not b.N; setup before loop runs once
func FuzzX(f *testing.F) { f.Add(1, 2); f.Fuzz(func(t *testing.T, a, b int) {}) }
```
- `t.Setenv`/`t.Chdir` panic in a `t.Parallel()` test. Use `t.TempDir()`, `t.Cleanup`, `t.Context()`.
- `go test -race -shuffle=on ./...`, `go test -run '^TestX$/sub' ./pkg`, `go test -run '^$' -bench . -benchmem`, `go test -fuzz FuzzX -fuzztime 30s ./pkg` (one package only), `-count=1` to skip the cache.

## Commands
```sh
go mod init github.com/you/proj; go mod tidy   # `go mod tidy -diff` in CI (non-zero if dirty)
go get example.com/m@v1.2.3; go get -u ./...; go get go@1.26
go get -tool golang.org/x/tools/cmd/stringer; go tool stringer -type=Kind  # tools in go.mod, no tools.go
go vet ./...; gofmt -l .; go fix -diff ./... && go fix ./...   # modernizers: wg.Go, any, SplitSeq, min/max, rangeint...
go run golang.org/x/vuln/cmd/govulncheck@latest ./...
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w -X main.version=$VER" -o bin/app ./cmd/app
go version -m bin/app; go doc -http
```
VCS info is embedded automatically (`debug.ReadBuildInfo()`, `-buildvcs=false` turns it off). `-X` only sets package-level `string` vars. Mark deprecated wrappers with `//go:fix inline` above the func, const or alias so `go fix` rewrites callers.

## Layout
`go.mod`, `cmd/<app>/main.go` (thin: parse flags, wire deps, call `run(ctx) error`), `internal/<pkg>` (not importable by other modules). Libraries put the package at the module root. Skip `pkg/`, `util`, `common`. Interfaces live with the consumer and stay small. Return concrete types. No `Get` prefix. Initialisms keep their case: `userID`, `ServeHTTP`. Use `log/slog` (`slog.Info("msg", "k", v)`) for structured logs.

## Errors you will hit
| Message | Fix |
|---|---|
| `declared and not used: x` / `"strings" imported and not used` | use or delete it |
| `mismatched types int and int64` | explicit conversion `int64(x)` |
| `T does not implement I (method M has pointer receiver)` | pass `&T{}` |
| `import cycle not allowed` | move shared types to a third package |
| `assignment to entry in nil map` | `m := make(map[K]V)` / init in constructor |
| `all goroutines are asleep - deadlock!` | unbuffered send with no receiver, or Wait without Done |
| `concurrent map writes` | `sync.Mutex`/`sync.Map`; find it with `-race` |
| `range function continued iteration after ... returned false` | iterator ignored `yield`'s false |
| `non-constant format string in call to fmt.Printf` | `fmt.Print(s)` or `Printf("%s", s)` |
| `X requires go1.N or later` | raise the `go` line or avoid the API |
