---
name: dafny
description: "Version-correct, idiomatic Dafny for the installed toolchain (Dafny 4.11.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Dafny code."
---

# Dafny 4.11 — writing code that verifies and ships

Everything below was checked against Dafny 4.11.0.

## Commands
```sh
dafny verify dfyconfig.toml                 # exit 0 ok,2 parse/type,3 compile,4 verify
dafny run --no-verify main.dfy -- a b       # args after --; Main(args: seq<string>), args[0] = program name
dafny run main.dfy --input other.dfy        # extra source files for run
dafny test dfyconfig.toml                   # runs @Test / {:test} methods; exit 3 on failure
dafny build -t:py dfyconfig.toml -o out/app # cs(default) java js py go rs
dafny build -t:lib src/L.dfy -o acme.doo    # verified library; consumers: --library acme.doo
dafny format src/*.dfy                      # --check for CI (exit 5 if unformatted)
dafny audit file.dfy                        # lists assumptions/axioms
```
- **Warnings are fatal** (non-zero exit) unless `--allow-warnings`. Fix them.
- `--library` code is **never compiled**; to run, pass sources (`include "x.dfy"`, `--input`, project `includes`).
- Targets: cs → `dotnet out/app.dll`; js needs `npm i bignumber.js`; go needs `goimports`; rs needs `--enforce-determinism`; java → `java -jar out/app.jar`; py → `python3 out/app-py/__main__.py`.
- `dafny format dfyconfig.toml` fails with `standard-libraries = true` (tries the stdlib `.doo`); list files.
- CI: `dafny-lang/setup-dafny-action@v1` with `dafny-version: "4.11.0"`.

## Project layout
```
dfyconfig.toml   src/*.dfy   test/*.dfy
```
```toml
includes = ["src/**/*.dfy", "test/**/*.dfy"]
[options]
standard-libraries = true
warn-shadowing = true
```
Use one unique top-level module (`module Acme.Core {..}`). **Siblings import relatively**: in `module Acme.App` write `import opened Core`; `import Acme.Core` there fails with "module definition contains a cycle".

## Dafny 4 syntax (old tutorials are wrong)
- `function`/`predicate` are compiled. `function method` is a parse error. Spec-only: `ghost function`, `ghost predicate`.
- `function F(..): T { spec } by method { imperative body }`: spec for proofs, loop at runtime.
- @-attributes precede the decl: `@Test`, `@IsolateAssertions`, `@ResourceLimit("1e6")`, `@Axiom`, `@VerifyOnly`. `{:test}` still works.
- `opaque function F`, then `reveal F();`. `hide F;`/`hide *;` drop bodies in a proof.
- `for i := 0 to n` / `for i := n downto 0` (bounds implicit). `forall c <- s :: P(c)`.
- New in 4.11: reals `1.5e3`, `.5`; redeclaring inherited trait methods.

## Standard library (`--standard-libraries`)
Always `import` (bare `Std.X.F` → "unresolved identifier: Std"; no flag → "module Std does not exist").
```dafny
import opened Std.Wrappers      // Option Some/None, Result Success/Failure, Outcome Pass/Fail
import Std.Collections.Seq      // Map Filter FoldLeft Join Split MergeSortBy IndexOf Reverse ToSet All
import Maps = Std.Collections.Map  // Maps.Get(m,k): Option; Remove, Union, Restrict
import Std.Strings              // OfNat OfInt ToNat ToInt OfBool OfChar
import Std.FileIO               // ReadUTF8FromFile(p) -> Result<string,string>; WriteUTF8ToFile -> Outcome<string>
import Std.Math                 // Min Max Abs
import opened Std.Arithmetic.Mul // LemmaMulInequality(x,y,z); DivMod: LemmaModMultiplesBasic(m,p)
function AddStrs(a: string, b: string): Result<nat, string> {
  var x :- ParseNat(a);  // propagates Failure
  var y :- ParseNat(b);
  Success(x + y)
}
// In methods: var v :- expect M();   (halts if Failure)
```
- `.GetOr(d)`, `.ToResult(e)`, `.ToOption()`, `.MapFailure(f)`. 4.11: `FromUTF8Checked` returns `Result`; `Seq.SetToSeq` removed.
- `Seq.Map`/`Filter` are `opaque`: `reveal Seq.Filter();` and pass a **named** predicate (`Seq.Filter(IsPos, xs)`); equal lambda literals are distinct terms.
- JSON: `Std.JSON.API.Deserialize`/`Serialize` use `seq<uint8>`; convert via `Std.Unicode.UnicodeStringsWithUnicodeChar.ToUTF8Checked(s)` (Option) / `FromUTF8Checked` (Result).
- Nonlinear goals are flaky in Z3: call `Std.Arithmetic` lemmas.

## Traps that compile wrongly or not at all
- **Brace-less statement `match` swallows all following statements into its last case.** In methods write `match r { case A => .. case B => .. }`.
- No method calls in expressions (`var z := Inc(1) + 1;` fails): bind first. Functions can't call methods or `print`.
- Arrays: `a.Length`, `a[..]` (not `|a|`). Seq is immutable: `s := s[i := v]`.
- `"n=" + 1` is a type error: `Strings.OfInt(1)`. Digits: `(c as int) - ('0' as int)`.
- Compiled quantifiers/`:|` must be bounded (`x in s`, `0 <= i < n`), else the var turns ghost: "ghost variables such as b are allowed only in specification contexts".
- `:|` in a function must be uniquely determined; in methods OK unless `--enforce-determinism`.
- `/` and `%` are Euclidean: `-7 / 2 == -4`, `-7 % 2 == 1`.
- Strings nested in datatypes print as `['a']`, datatypes module-qualified: format output yourself.
- `datatype D extends T` needs `--general-traits=datatype --type-system-refresh`; otherwise only classes extend traits.
- Bodyless lemma or `assume P;` warns (build fails). `@Axiom`/`assume {:axiom}` mark trust (reported by `dafny audit`); never use them to make proofs "pass".

## Error → fix
| Message | Fix |
|---|---|
| `a postcondition could not be proved on this return path` | Stronger invariant, intermediate `assert`s, lemma call |
| `this invariant could not be proved to be maintained by the loop` | Fix invariant; assert slice facts (`xs[..i+1][..i] == xs[..i]`) |
| `cannot prove termination; try supplying a decreases clause` | `decreases n - i` / lexicographic `decreases a, b` |
| `insufficient reads clause to read field` | `reads this` / `reads this, Repr` on the function |
| `assignment might update an object/array element not in the enclosing context's modifies clause` | `modifies this` / `modifies a` |
| `index out of range` / `element might not be in domain` | `requires 0 <= i < a.Length` / `k in m` guard |
| `value does not satisfy the subset constraints of 'nat'` / `might violate newtype constraint` | Prove bounds (`requires`/invariant) |
| `the type of this variable is underspecified` | Annotate: `var m: map<int,string> := map[];` |
| `the result of a set comprehension must be finite` | Bound it: `set x \| x in s && P(x)` |
| `a call to a possibly non-terminating method is allowed only if...` | Caller also needs `decreases *` |

## Verification workflow
- One symbol: `--filter-symbol=Name` or `--filter-position=file.dfy:42`.
- Failing conjunct: `--isolate-assertions`; values: `--extract-counterexample`.
- Deterministic budget: `--resource-limit=1e6` ("out of resource") over time limits (default 30 s).
- Inductive lemmas: explicit base case; assert slice identities (`(a + b)[1..] == a[1..] + b`) before the recursive call. An empty body means proved, not skipped.
- Slow proofs: `opaque` helpers, `hide *`, split into lemmas; `assert P by { reveal F(); }` keeps facts local.

## Classes (dynamic frames)
```dafny
class Stack<T> {
  ghost var Contents: seq<T>
  ghost var Repr: set<object>
  var data: array<T>
  var n: nat
  ghost predicate Valid() reads this, Repr
  { this in Repr && data in Repr && n <= data.Length && Contents == data[..n] }
  method Push(x: T)
    requires Valid() modifies Repr
    ensures Valid() && fresh(Repr - old(Repr)) && Contents == old(Contents) + [x]
  // body: grow data if full, set data[n], n := n + 1, Contents := Contents + [x]
}
```
Constructors `ensures Valid() && fresh(Repr)`; caller loops keep `invariant s.Valid() && fresh(s.Repr)`. `{:autocontracts}` automates simple cases.

## Fast compiled code
- `int`/`nat` are BigIntegers; bounded newtypes compile to native ints: `newtype u64 = x: int | 0 <= x < 0x1_0000_0000_0000_0000`, `newtype i32 = x: int | -0x8000_0000 <= x < 0x8000_0000`.
- Self tail calls become loops; prefer accumulators or `by method` over deep recursion.
- Mutate `array<T>` (`new int[n](i => 0)`, `new int[] [1, 2]`); bulk: `forall i | 0 <= i < a.Length { a[i] := 0; }`.
