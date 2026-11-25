---
name: octave
description: "Version-correct, idiomatic Octave for the installed toolchain (GNU Octave (aarch64-apple-darwin24.6.0) version 11.3.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Octave code."
---

# GNU Octave 11.3: writing correct Octave

Checked on Octave 11.3.0. Don't assume newer MATLAB features exist.

## Running
```sh
octave-cli -q -f script.m                       # -f/--norc: skip ~/.octaverc
octave-cli -q -f -p inst --eval 'disp(f(2))'    # -p DIR: prepend to path
octave --no-gui -q -f plot_job.m                # headless plotting (qt)
```
- An uncaught `error` gives exit status 1. `exit(n)` sets the code.
- Shebang `#!/usr/bin/env -S octave-cli -q -f`. `argv()` is a column cell.
- `octave-cli` has only `fltk`, so `print` of a `figure("visible","off")` fails with "requires visible figure". Use `octave --no-gui` instead: `h=figure("visible","off"); plot(..); print(h,"-dpng","-r100","o.png"); close(h)`.
- In a shell `--eval '...'`, a transpose `'` ends the quoted string. Put the code in a `.m` file.

## Files and layout
- A file whose first statement is `function` is a function file. Its name must match the first function. Later functions in it are file-local.
- A script may define functions, but only *before* the line that calls them. MATLAB-style functions at the end of the script fail with `'g' undefined`. Start a functions-first script with `1;`.
- `private/`, `+pkg/` (call `mypkg.fn()`), `@class/` and classdef `Name.m` all work.
- Layout: `DESCRIPTION COPYING inst/*.m inst/+mypkg/ inst/private/ src/*.cc tests/run_tests.m`

## Missing in 11.3: what to use instead
| Missing | Use |
|---|---|
| `string` class, `strings` | char row vectors. `"..."` is char *with* escapes, `'...'` is char without escapes |
| `contains split join splitlines replace compose pad` | `!isempty(strfind(s,p))`, `strsplit`, `strjoin`, `regexp(s,"\n","split")`, `strrep`/`regexprep`, `sprintf` |
| `readmatrix writematrix readtable table readlines writelines` | `dlmread`/`csvread`, `dlmwrite`/`csvwrite`, `textscan`, `fileread`, `fprintf` |
| `datetime` | `datenum`, `datestr(d,"yyyy-mm-dd")`, `strftime` |
| `MException(...)`, `throw`, `getReport` | `error("pkg:id","fmt %d",x)`, `rethrow(err)`. `catch err` gives a struct-like value with `.message .identifier .stack` |
| `histcounts`, `discretize` | `histc`, `accumarray`, `lookup` |
| `arguments` blocks, classdef property validators `x (1,1) double` | parsed but **ignored**, with a warning. Use `validateattributes`/`inputParser`/`set.x` methods |
| classdef `enumeration`, `events` | syntax error / invalid handle |
| `**` operator | syntax error. Use `^` / `.^` |
| `isMATLABReleaseOlderThan` | `compare_versions(OCTAVE_VERSION,"11.0.0",">=")` |

Present: `containers.Map`, `jsonencode/jsondecode` (no `"PrettyPrint"` in this build), `startsWith/endsWith`, `erase`, `inputParser`, `validatestring`, `onCleanup`, `evalc`, `isfile/isfolder`, `rms rmse mape`, `xline/yline`, `assert_equal`.

## Octave 10/11 breaking changes
- `cellfun` with UniformOutput errors when outputs differ in class ("all values should be of the same type"). Make the classes match, or pass `"UniformOutput", false`.
- `mean` rejects char. `var`/`std` reject integers. Use `double(x)`.
- `min max sum prod any all cumsum` take `"all"`, vecdim, `"omitnan"`.
- `qr(A)` with one output returns `R`. `polyfit` S has `rsquared`. `S.X` is deprecated, use `S.V`.
- `colorbar(location, ...)` takes the location first. `cell(2.5)` now errors (non-integer size).
- Removed: `shift` (use `circshift`), extra trailing args to `fminsearch` (use an anonymous fn), `load -force/-import`. `dsearch` is deprecated: use `dsearchn`.
- `pkg install name` resolves file → URL → index, so `-forge` is not needed. `pkg search kw`. Broadcasting is warning-free, including sparse.

## Style (Octave style guide)
- Indent 2 spaces and comment with `#`/`##`.
- Close blocks with `endif endfor endwhile endfunction endswitch end_try_catch`.
- Use `!` / `!=` and double quotes.
- Put a space before call parens but not index parens: `y = max (x(:,1), 0);`. Write `if (cond)`.
- Names are lowercase_underscore. Prefix error messages with the function name: `error ("myfn: X must be numeric")`.

## Correct and fast idioms
- Vectorize. A 2e5-iteration scalar loop was about 80× slower than `sum((1:N).^2)`.
- Preallocate with `zeros(n,1)` / `cell(n,1)`. Avoid `x(end+1)=` in loops.
- `cellfun("isempty", c)` is about 40× faster than `@isempty`. Name-string fast paths: `isempty islogical isnumeric isreal length numel prodofsize size isclass`.
- Octave syntax: `+= -= *= ++`, `do ... until (c)`, `unwind_protect ... unwind_protect_cleanup ... end_unwind_protect` (guaranteed `fclose`).
- Compare strings with `strcmp`, `strcmpi` or `ismember(s, list)`. `==` compares elementwise and errors on unequal lengths.
- `strsplit("a,b,,c", ",")` **collapses** delimiters (3 parts). Pass `"CollapseDelimiters", false` to keep the empty field.
- `["ab"; "abc"]` pads silently (MATLAB errors). `strcat` trims trailing spaces of char args, so use `[a b]`.
- Integers saturate and round: `int32(7)/2 == 4`, `abs(int8(-128)) == 127`. `idivide` truncates (`"fix"`).
- Mixed integer classes: `int8 + int16` errors, and `int8(1)+2.5` gives int8. `sum(intX)` returns double, so pass `"native"` to keep the class.
- Struct arrays: `struct("a", {1,2})` is 1×2. A cell-valued field needs `{{...}}`. Also `[s.a]`, `[s.a] = deal(0)`, `s.(name)`.
- Defaults: `if (nargin < 2) k = 1; endif`. Bad call in a function: `print_usage ()`.
- `assert (x, y, tol)`: tol > 0 is absolute, tol < 0 is relative.

## Tests: `%!` blocks after `endfunction`
```octave
%!assert (addtwo (1), 3)
%!assert (addtwo (0.1), 2.1, eps)
%!error <Invalid call> addtwo ()
%!error id=bad:type bad ("s")
%!warning <divide> warning ("my:w", "divide by zero");
%!test
%! x = addtwo (zeros (2));
%! assert (x, 2 * ones (2));
%!shared a
%! a = 3;
```
- Ways to run: `test addtwo`, `[npass, ntotal] = test ("f.m", "quiet", stdout)`, `oruntests ("/abs/inst")` (relative paths warn), or `pkg test mypkg` (writes fntests.log).
- `test` does **not** add the file's dir to the path, so call `addpath` first.

CI runner `tests/run_tests.m`, run as `octave-cli -q -f tests/run_tests.m`:
```octave
d = fullfile (fileparts (mfilename ("fullpath")), "..", "inst");
addpath (d);
f = [dir(fullfile (d, "*.m")); dir(fullfile (d, "+*", "*.m"))];
nfail = 0;
for k = 1:numel (f)
  [n, nmax] = test (fullfile (f(k).folder, f(k).name), "quiet", stdout);
  nfail += nmax - n;
endfor
exit (nfail > 0);
```

## Packaging
Write `DESCRIPTION`. Without an INDEX file, `Categories` is required or install fails:
```
Name: mypkg
Version: 0.1.0
Date: 2026-11-25
Author: A. Person <a@example.org>
Maintainer: A. Person <a@example.org>
Title: Short title
Description: One paragraph.
License: GPLv3+
Depends: octave (>= 10.1.0)
Categories: Utilities
```
```sh
tar czf mypkg-0.1.0.tar.gz mypkg-0.1.0/    # single top-level dir
octave-cli -q -f --eval 'pkg install mypkg-0.1.0.tar.gz; pkg load mypkg; pkg test mypkg'
```
- Sandbox install: `pkg prefix DIR DIR; pkg local_list DIR/octave_packages`.

## Compiled extensions (C++17)
```cpp
#include <octave/oct.h>
DEFUN_DLD (twice, args, , "y = twice (x)")
{
  if (args.length () != 1)
    print_usage ();
  return ovl (args(0).array_value () * 2.0);
}
```
- `mkoctfile twice.cc` builds `twice.oct`.
- `mkoctfile --mex addm.c` builds `addm.mex` (use `mexFunction`, `mexErrMsgIdAndTxt`).
- Flags: `-I -L -l -o -g -v`.

## Error → fix
- `'x' undefined`: a typo, a missing `addpath`/`pkg load`, or a script function defined after its use.
- `nonconformant arguments (op1 is 1x2, op2 is 1x3)`: the shapes don't match. Check `.*` vs `*`, or reshape with `(:)`.
- `subscripts must be either integers 1 to (2^63)-1 or logicals`: you indexed with 0 or a fraction. Use `round` or a logical mask.
- `binary operator '+' not implemented for 'cell' by 'scalar'`: use `c{k}` or `cellfun`.
- `variable "x" used as function in command style expression`: a spacing problem. Write `a - b`, not `a -b`.
- `function name 'g' does not agree with function filename`: the script starts with `function`. Prepend `1;`.
