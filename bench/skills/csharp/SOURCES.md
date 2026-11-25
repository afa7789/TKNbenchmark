# Sources

## Official docs and release notes (.NET 11 / C# 15)
- https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-15 — C# 15 feature list and syntax: collection expression `with(...)`, unions, `closed`, extension indexers, labeled break/continue, memory-safety preview.
- https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/union — union semantics: generated struct, `Value`, boxing, null pattern, CS8121 on `is UnionType`, exhaustiveness/CS8655, custom `[Union]` types.
- https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/breaking-changes/compiler%20breaking%20changes%20-%20dotnet%2011 — `with(` now collection args (use `@with`), `union`/`closed` contextual keywords (`@union`), span collection-expression safe-context change, `nameof(this.X)` in attributes.
- https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/overview — runtime/library/SDK highlights (Runtime Async, Process helpers, Zstandard, LINQ joins, EqualityComparer.Create, Random generics, new Stream types).
- https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/libraries — exact API shapes: `Process.RunAndCaptureTextAsync`, `LeftJoin`/`FullJoin`/tuple `Join`, `Random.NextInteger<T>`, `StringStream`, STJ union support and JSONL.
- https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-11/sdk — file-based app `#:include`, `dotnet run -e`, MTP `dotnet test` options, xUnit v3 template flags, MSBuild server default, AOT optimized publish opt-in.
- https://learn.microsoft.com/en-us/dotnet/core/compatibility/11 — .NET 11 breaking changes (Extensions packages in shared framework, BackgroundService failure throws from RunAsync, DateOnly/TimeOnly TryParse, Math.Round, NativeAOT lib prefix, etc.).

## Style guides
- https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/coding-style/coding-conventions — official conventions: file-scoped namespaces, usings outside namespace, `var` only when obvious, collection expressions, raw strings, `required`, primary-ctor param casing.
- https://raw.githubusercontent.com/dotnet/runtime/main/docs/coding-guidelines/coding-style.md — runtime style: Allman braces, `_camelCase`/`s_` fields, explicit visibility, keywords over BCL names, seal private/internal types.

## Agent rules / skills published by .NET developers
- https://raw.githubusercontent.com/dotnet/msbuild/HEAD/AGENTS.md — dotnet org agent rules: nullable on, `is null`, pattern matching, spans in hot paths, Frozen/Immutable collections, warnings-as-errors, read first build error first.
- https://awesome-copilot.github.com/instruction/csharp/ — widely used Copilot C# instructions: file-scoped namespaces, `nameof`, `is null`, trust nullable annotations, no Arrange/Act/Assert comments.
- https://raw.githubusercontent.com/dotnet/skills/HEAD/README.md — official dotnet/skills plugin catalog (incl. a dotnet11 plugin).
- https://raw.githubusercontent.com/dotnet/skills/main/plugins/dotnet11/skills/process-api-net11/SKILL.md — .NET 11 Process API guidance and deadlock gotchas (drain pipes, argument lists, no `.Result`).
- https://raw.githubusercontent.com/dotnet/skills/main/plugins/dotnet11/skills/system-text-json-net11/SKILL.md — `JsonNamingPolicy.PascalCase`, `GetTypeInfo<T>()` needs a TypeInfoResolver, file-based apps disable reflection JSON.
- https://cdn.jsdelivr.net/gh/aaronontheweb/dotnet-skills@master/README.md — popular community .NET skill set: records/immutability, sealed by default, Span, composition.
- https://cdn.jsdelivr.net/gh/aaronontheweb/dotnet-skills@master/skills/csharp-coding-standards/SKILL.md — concrete rules: CancellationToken everywhere, `ThrowIfNull` guards, no `.Result`/`.Wait()`, `readonly record struct` value objects.
- https://devblogs.microsoft.com/dotnet/instructions-hygiene-what-frontier-models-still-need-you-to-say — what agents need stated: exact build/test commands, chosen conventions (e.g. TimeProvider), hard constraints.

## Verified locally (SDK 11.0.100, osx-arm64)
All commands, templates, snippets and error codes in SKILL.md were built/run in a scratch dir: templates (`console`, `classlib`, `xunit --xunit-version v3`, `webapi`, `buildprops`, `packagesprops`, `globaljson`), `.slnx` default, CPM (NU1008), NU1510 pruning, MTP `--filter` rejection, file-based app reflection-JSON failure, AOT link fix, analyzer errors CA1050/CA1707/CA1305/CA1848/CA1861/CA1873, and compiler errors CS9215/CS8509/CS8121/CS9381/CS0029.
