---
name: ocaml
description: "Version-correct, idiomatic OCaml for the installed toolchain (The OCaml toplevel, version 5.5.2): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing OCaml code."
---

# OCaml 5.5 (5.5.2) for agents

Target is OCaml 5.5.2: multicore runtime, effects, no flambda by default. Use dune 3.x and opam 2.x.
Write 5.x code, not 4.x. Don't use `Pervasives`, `Stream` or `Genlex` (removed), and don't use
`Thread` for parallelism. Reach for the stdlib below before adding deps.
Check what's installed (`ocamlfind list`, `which ocamlformat`) first.

## Layout and commands

```
dune-project   (lang dune 3.25) (generate_opam_files true) (package (name app) ...)
bin/dune       (executable (public_name app) (name main) (libraries app))
lib/dune       (library (name app))      ; lib/foo.ml is App.Foo from outside
test/dune      (test (name test_app) (libraries app))
```
- `dune init proj app` scaffolds this. Replace the placeholder `source`/`authors` fields.
- `dune build`: in the dev profile many warnings are **errors**. `--release` makes them plain warnings.
- `dune build @check`: fastest type-check. `-w` watches.
- `dune exec app -- args`, `dune test`, `dune promote` (accept expect/cram diffs).
- `dune build -p app @install`: the release build used by opam.
- `dune fmt` needs the `ocamlformat` binary and a `.ocamlformat` (`profile = default`, plus a pinned `version=`).
- Deps: `opam switch create . --deps-only`, then `opam install . --deps-only --with-test`.
- Publish: write `CHANGES.md` (`# x.y.z` headings), then `dune-release bistro`, which tags, lints, builds the tarball and opens the opam-repository PR.
- Libraries that ship with the compiler: `unix`, `str`, `threads`. `Domain`, `Mutex`, `Atomic`, `Effect` need no library.
- Scripts: `ocaml file.ml`, with `#use "topfind";;` and `#require "unix";;` at the top.
- Give every lib module a `.mli`, with abstract types unless callers must match.

Cram tests need no deps. `test/dune`: `(cram (deps %{bin:app}))`. Then `test/cli.t/run.t`:
```
  $ app nope
  not an int: nope
  [1]
```
Output lines are indented 2 spaces, and `[n]` is the exit code. A plain `(test)` fails when its exe exits non-zero (`assert`).
Common deps: `alcotest`, `ppx_expect` (`(inline_tests) (preprocess (pps ppx_expect))`).

## Stdlib 5.3–5.5 (verified; mind the labels)

```ocaml
String.split_first ~sep:"=" "k=v=w"         (* Some ("k","v=w"); split_last *)
String.split_all ~sep:"," ~drop:String.is_empty "a,,b" (* ["a";"b"] *)
String.replace_all ~sub:"a" ~by:"o" s        (* replace_first/_last *)
String.includes ~affix:"nan" "banana"        (* substring test *)
String.find_first ~sub:"na" s                (* int option; find_last *)
String.find_first_index Char.Ascii.is_digit s
String.take_first 3 s; drop_first; cut_first (* pair *); *_last
String.drop_first_while (fun c -> c = ' ') s (* take_/cut_ *_while *)
String.is_empty; String.of_char; String.edit_distance a b
List.take n l; List.drop n l  (* n<0: [] / l, no raise since 5.4 *)
List.take_while; drop_while; is_empty; find_index; filter_mapi; split_map
Option.Syntax; Result.Syntax  (* let* let+ and* and+ *)
Option.product; for_all; exists; to_result ~none; Result.product
Hashtbl.find_and_replace h k v; Hashtbl.find_and_remove h k (* old opt *)
Int.fdiv/cdiv/ediv/erem; Int.popcount; Int.leading_zeros
Domain.recommended_domain_count (); Domain.self_index (); Domain.count ()
In_channel.with_open_text f In_channel.input_all   (* input_lines *)
In_channel.fold_lines (fun acc line -> ...) init ic
Out_channel.with_open_text f (fun oc -> Out_channel.output_string oc s)
let add a b = let open Option.Syntax in let* x = a in let+ y = b in x + y
```
Modules: `Dynarray` (growable array: `create`, `add_last`, `get`, `pop_last_opt`),
`Iarray` (`[| 1; 2 |] : int iarray`), `Pqueue.MakeMin (Int)` (`create`, `add`,
`pop_min : t -> elt option`), `Pair`, `Char.Ascii`, `Lazy.Mutexed`
(domain-safe lazy), `Type.Id`, `Repr.phys_equal`.

## Language (5.3–5.5)

```ocaml
type _ Effect.t += Ask : int Effect.t
let run f = match f () with
  | v -> v
  | effect Ask, k -> Effect.Deep.continue k 42   (* resume k exactly once *)
let p = (~x:1, ~y:2)  let (~x, ~y) = p          (* labelled tuples, 5.4 *)
type c = { mutable n : int [@atomic] }           (* 5.4 *)
let bump r = Atomic.Loc.fetch_and_add [%atomic.loc r.n] 1
(* 5.5 modular explicits *)
let show_all : (module S : Show) -> S.t list -> string =
  fun (module S) xs -> String.concat "," (List.map S.show xs)
let f () = let type t = A | B in ...   (* 5.5; let exception/open too *)
let both (id : 'a. 'a -> 'a) = (id 1, id "x")    (* 5.5 poly param *)
```
Breaking changes in 5.5: `let rec (module M : S)` is removed. Abstract types of the current module are
no longer provably distinct in GADT matches, so use private abbreviations instead.

## Concurrency

- `Domain.spawn f |> Domain.join` runs in parallel. Use about `recommended_domain_count () - 1` long-lived workers, not one domain per task.
- Use `Atomic.make/get/set/incr/fetch_and_add/compare_and_set` for shared state, and `Mutex.protect m (fun () -> ...)`, which is exception-safe.
- `Hashtbl`, `Queue`, `Buffer`, `Dynarray` and `ref` are not domain-safe, so keep them domain-local or behind a mutex. `Random`'s default state is domain-local.
- `Thread` is concurrency, not parallelism. Async IO: `eio` or `lwt`.

## Correct and fast

- `List.map/filter_map/init/concat_map` and `@` are tail-mod-cons. Your own builders should use `let[@tail_mod_cons] rec` or an accumulator plus `List.rev`. Assert a tail call with `(f [@tailcall]) x`.
- Build strings in a `Buffer` and join with `String.concat`, not `^` in a loop.
- Use `Hashtbl.replace` (`add` shadows) and `find_opt` instead of `find` plus `Not_found`.
- For `Map.Make (String)`, write `M.update k (function None -> Some 1 | Some n -> Some (n + 1)) m`.
- Polymorphic `=`/`compare` are slow, raise on closures, and `nan = nan` is false. Use `Int.equal`/`String.equal`/`Float.equal`. `==` is physical equality, so never use it on strings.
- Argument and operand evaluation order is unspecified, and in practice right-to-left. In `f (read ()) (read ())` the second call runs first, so `let`-bind first.
- `Printf` buffers output: flush with `%!` before `exit` or a crash. In `Format`, use boxes (`"@[%a@]"`), because `@ `/`pp_print_space` outside a box prints a newline.
- Clean up with `Fun.protect ~finally` / `with_open_*`.
- Expected failures go in `('a, string) result` or ``[`Msg of string]``. Raise exceptions (`Invalid_argument`, `Failure`) only for bugs.
- No catch-all `with _ ->`, because it swallows `Out_of_memory` and `Stack_overflow`. To re-raise and keep the trace, use `Printexc.raise_with_backtrace e (Printexc.get_raw_backtrace ())`, and run with `OCAMLRUNPARAM=b`.
- Don't use `| _ ->` on your own variants, so that warning 8 flags new cases.
- Prefer patterns or `_opt` functions (`int_of_string_opt`, `List.nth_opt`) over `List.hd`/`Option.get`.
- Without flambda (`ocamlopt -config | grep flambda`), `-O3` does nothing. Speed comes from allocating less, from `Array`/`Bytes` loops, and from `float array`, which is unboxed.

## Errors → fixes

- `Error (warning 26 [unused-var])` (also 27/32/33): delete the binding or prefix it with `_`. Don't disable warnings globally.
- `Error (warning 8 [partial-match]) ... not matched: Blue`: add the missing case.
- `Unbound value fact` plus the hint "add the rec keyword": write `let rec`.
- `contains the non-generalizable type variable(s): '_weak1`: comes from a top-level `ref []` or a partial application. Annotate the type (`let c : int list ref = ref []`) or eta-expand.
- `The constant 0.5 has type float but ... int`: use `+.`/`*.` and `float_of_int`. There is no implicit numeric conversion.
- `if c then a; b`: `b` always runs. Wrap branches in `( ... )`/`begin ... end`, and parenthesize nested `match`/`try`.
- `implementation ... does not match the interface`: the `.mli` and `.ml` disagree, often because of a weak type.
- `Unbound module Foo`: add the library to `(libraries ...)`. Modules of a wrapped lib are `Lib.Foo` from outside.
- `Continuation_already_resumed`: you resumed an effect continuation twice.
