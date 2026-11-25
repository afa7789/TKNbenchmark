---
name: csharp
description: "Version-correct, idiomatic C# for the installed toolchain (.NET SDK 11.0.100): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing C# code."
---

# C# 15 / .NET 11 (SDK 11.0.100)

`net11.0` defaults to C# 15; don't set `LangVersion` (`preview` only for the memory-safety preview). Snippets verified on SDK 11.0.100.

## Layout and commands
```sh
dotnet new sln -n Acme                 # writes Acme.slnx (XML), not .sln
dotnet new console -o src/Acme.Cli; dotnet new classlib -o src/Acme.Core
dotnet new xunit --xunit-version v3 -o tests/Acme.Tests   # xUnit v3 on Microsoft.Testing.Platform
mv tests/Acme.Tests/global.json .      # MTP runner config must be at repo root
dotnet sln add src/Acme.Cli src/Acme.Core tests/Acme.Tests
dotnet reference add src/Acme.Core --project tests/Acme.Tests
dotnet package add Polly --project src/Acme.Core
dotnet new buildprops; dotnet new packagesprops; dotnet new editorconfig
dotnet build -c Release; dotnet test   # or --project tests/Acme.Tests
dotnet test --filter-method "*Parse*"  # MTP: also --filter-class / --filter-query; --filter fails
dotnet format --verify-no-changes      # CI gate; `dotnet format` fixes
dotnet run --project src/Acme.Cli -e KEY=V -- args
dotnet publish src/Acme.Cli -c Release -r osx-arm64 --self-contained -p:PublishSingleFile=true
```
Root `Directory.Build.props` applies to every project below it, file-based apps included:
```xml
<Project><PropertyGroup>
  <TargetFramework>net11.0</TargetFramework><Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings><TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  <AnalysisLevel>latest-recommended</AnalysisLevel><EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
</PropertyGroup></Project>
```
With `Directory.Packages.props` (CPM), versions go only in `<PackageVersion>`; `Version=` on `<PackageReference>` is **NU1008**.

`global.json`: `{"sdk":{"version":"11.0.100","rollForward":"latestFeature"},"test":{"runner":"Microsoft.Testing.Platform"}}`

**File-based apps** run with `dotnet run app.cs`, `dotnet app.cs`, or `./app.cs` with a `#!/usr/bin/env dotnet` shebang. Directives: `#:package Name@1.2.3`, `#:project ../Lib`, `#:sdk Microsoft.NET.Sdk.Web`, `#:property K=V`, `#:include helpers.cs`. They're AOT-configured: reflection `JsonSerializer` throws *"Reflection-based serialization has been disabled"*; use a source-generated context or `#:property PublishAot=false`. `dotnet project convert app.cs` makes a .csproj.

## C# 15
```csharp
List<string> l = [with(capacity: 32), .. src];      // ctor args; must be first element
HashSet<string> s = [with(StringComparer.OrdinalIgnoreCase), "a", "A"];

public union Pet(Dog, Cat);           // struct, implicit conversion from each case
Pet p = new Dog("Rex");               // p.Value is object?; value-type cases are boxed
string n = p switch { Dog d => d.Name, Cat c => c.Name, null => "none" }; // default(Pet): null

public closed record Shape;           // implicitly abstract; subtypes only in this assembly
public record Circle(double R) : Shape;
public record Square(double S) : Shape;
double A(Shape x) => x switch { Circle c => Math.PI * c.R * c.R, Square q => q.S * q.S }; // exhaustive

public static class SeqExt { extension(IEnumerable<int> seq) { public int this[int i] => seq.ElementAt(i); } }

outer: for (int r = 0; r < h; r++)
    for (int c = 0; c < w; c++) { if (skip) continue outer; if (done) break outer; }
```
- Union patterns test the contents: `p is Pet` is **CS8121**; use `p is not null`.
- STJ writes a union as its case value (`42`, `"x"`); object cases deserialize with `[JsonUnion(TypeClassifier = typeof(JsonUnionTypeStructuralClassifier))]`.
- `closed` can't be combined with `sealed`, `abstract` or `static` (**CS9381**).
- C# has no dictionary expressions: `Dictionary<K,V> d = [..]` is **CS9215**. Use `new(StringComparer.Ordinal) { ["k"] = 1 }`.
- Inside a collection expression, `with(` now means constructor arguments; call a method named `with` as `@with(...)`. Identifiers named `union` or `closed` need `@`.

## C# 14
```csharp
public double Deg { get; set => field = Math.Max(value, -273.15); } // field keyword
node?.Next = other;                                                // null-conditional assignment
nameof(List<>);
public static class StrExt {
    extension(string s) { public bool IsBlank => string.IsNullOrWhiteSpace(s); }     // ext property
    extension(string) { public static string Csv(IEnumerable<string> x) => string.Join(",", x); } // string.Csv(..)
}
```
Extension blocks must be inside a non-generic, top-level `static class`.

## Day-to-day APIs (.NET 10/11)
```csharp
ProcessTextOutput r = await Process.RunAndCaptureTextAsync("git", ["status", "--porcelain"]);
int code = r.ExitStatus.ExitCode; string o = r.StandardOutput;  // drains both pipes, no deadlock
foreach (var (a, b) in xs.LeftJoin(ys, x => x.Id, y => y.Id)) { } // RightJoin, FullJoin, tuple Join
var byName = EqualityComparer<Person>.Create(p => p.Name);
int k = Random.Shared.NextInteger<int>(0, 10);
using Stream st = new StringStream(text, Encoding.UTF8);         // also ReadOnlyMemoryStream
var z = new ZstandardStream(dest, CompressionMode.Compress);     // System.IO.Compression
List<int> all = await GetAsync().Where(x => x > 0).ToListAsync(); // async LINQ is in the BCL
private readonly Lock _gate = new();                             // lock (_gate) {...}, not object
xs.CountBy(x => x.Kind); xs.Index(); Guid.CreateVersion7();
await Task.Delay(TimeSpan.FromSeconds(1), timeProvider, ct);    // inject TimeProvider, not DateTime.Now
```
- Remove the `System.Linq.Async` package. It now collides with the BCL (**CS0121** ambiguous `Where`).
- Now in the shared framework (a PackageReference gives **NU1510**; delete it): `Microsoft.Extensions.{Logging,DependencyInjection,Configuration,Hosting,Caching,Diagnostics,FileProviders}.Abstractions`, `.Options`, `.Primitives`. `Microsoft.Extensions.Hosting` is still a package.
- `IHost.RunAsync` throws if a `BackgroundService` faults. `options.GetTypeInfo<T>()` needs `TypeInfoResolver` set.

## Production idioms
- JSON for AOT/trim: `[JsonSerializable(typeof(Person))] internal partial class AppJson : JsonSerializerContext;` then `JsonSerializer.Serialize(p, AppJson.Default.Person)`.
- Logging: `[LoggerMessage(Level = LogLevel.Information, Message = "Tick {Now}")] private partial void LogTick(DateTimeOffset now);` in a `partial` class; direct `logger.LogX(..)` is **CA1848**; a method-call argument is **CA1873** (use a local).
- Host: `var b = Host.CreateApplicationBuilder(args); b.Services.AddHostedService<Worker>(); using IHost h = b.Build(); await h.RunAsync();`
- Minimal API: `WebApplication.CreateSlimBuilder`, `Services.AddValidation()` (DataAnnotations on records produce a 400 ProblemDetails), `Results<Ok<T>, NotFound>` with `TypedResults`, `AddOpenApi()`/`MapOpenApi()` (OpenAPI 3.2 at `/openapi/v1.json`).
- Async: flow `CancellationToken`; never `.Result`/`.Wait()`; xUnit v3: `TestContext.Current.CancellationToken`; libraries: `ConfigureAwait(false)`.
- `sealed` classes, `readonly record struct` values, `ArgumentNullException.ThrowIfNull` guards, `CultureInfo.InvariantCulture` parse/format (**CA1305**).
- Hot paths: spans, `SearchValues.Create(",;")`, `ToFrozenDictionary()`; constant array args → `static readonly` (**CA1861**).

## Errors → fixes
| Symptom | Fix |
|---|---|
| CS8509 not exhaustive (union/closed) | add missing case arm (+ `null` for unions) |
| CS0029 X → union | X isn't a case type; add it to `union(...)` |
| CA1050 types need a namespace | move types out of top-level `Program.cs` into a file-scoped namespace |
| CA1707 underscores in test names | `.editorconfig` `[tests/**.cs]` `dotnet_diagnostic.CA1707.severity = none` |
| `Unknown option '--filter'` | MTP: `--filter-method`/`--filter-class`/`--filter-query` |
| `NoMetadataForType`, IL2026/IL3050 | source-generated `JsonSerializerContext` |
| AOT `ld: library 'ssl' not found` (Homebrew SDK) | `LIBRARY_PATH=$(brew --prefix openssl@3)/lib:$(brew --prefix brotli)/lib:$(brew --prefix zstd)/lib dotnet publish -p:PublishAot=true` |
