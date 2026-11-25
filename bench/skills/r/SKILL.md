---
name: r
description: "Version-correct, idiomatic R for the installed toolchain (R version 4.6.2 (2026-10-29) -- \"Diversified Portfolio\"): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing R code."
---

# R 4.6.x: writing correct, modern R

Target: R 4.6.2 (`getRversion() >= "4.6.0"`). For older R, avoid the newer functions below or set `Depends: R (>= x.y)`.

## Base additions by version (verified on 4.6.2)
- **4.6**:
  - `x %notin% table`; `substr(s, 2, NULL)` (NULL = to the end)
  - `list.files(pattern = ".md", fixed = TRUE)`; `messageCondition(msg, class=)`
  - `match.arg(a, several.ok = "all")`; `bitstring(5L)`
  - `summary(<chr>)` now reports Length/N.unique/N.blank/nchar (`character.method = "factor"` restores the old form). Missing values print as `NAs`, not `NA's`, so update tests that match that text.
- **4.5**: `grepv(pat, x)`; `tools::sha256sum(files, bytes)`; `use("pkg", c("f1", "f2"))` attaches only those names; datasets `penguins`/`penguins_raw` (columns `bill_len`, `flipper_len`, `body_mass`).
- **4.4**:
  - `a %||% b`; `sort_by(df, ~ list(cyl, -mpg))`; `Tailcall(f, n - 1)`
  - `is.atomic(NULL)` is now FALSE; `NCOL(NULL)` is now 0
- **4.2/4.3**:
  - `if (c(TRUE, FALSE))` errors; `c(TRUE, TRUE) && x` errors
  - `df |> _$col` extraction works
- **Defunct/removed**:
  - `structure(NULL, a = 1)` errors; `is.R()` is gone
  - The default C++ standard is C++20, and `CXX_STD = CXX11/CXX14` is defunct.
  - The non-API C functions `ATTRIB`, `STRING_PTR`, `Rf_findVarInFrame3` and `BODY` now give check WARNINGs; use `R_getAttributes`, `R_getVar` or `R_mapAttrib`.

## Native pipe `|>`
- The right-hand side must be a call: `x |> sum()`, not `x |> sum`.
- The `_` placeholder must be a named argument and may appear only once: `mtcars |> lm(mpg ~ wt, data = _)`. `head(_, 2)` errors.
- Lambdas need parentheses: `x |> (\(v) v * 2)()`.
- Prefer `|>` in new code, but don't mass-convert `%>%` code (`.` semantics differ).

## Correct, fast idioms
- Use `seq_len(n)`/`seq_along(x)`, never `1:length(x)` (`1:0` is `c(1, 0)`).
- Use `vapply(x, f, numeric(1))` over `sapply()`, which can return a list (`sapply(list(), f)` is `list()`).
- Preallocate (`vector("list", n)`, `numeric(n)`). Growing with `c()` was about 2000 times slower at 1e5.
- For data frames, collect a list and call `do.call(rbind, lst)` once.
- Vectorise with `ifelse` (vectors; `if` for scalars), `cumsum`, `rowSums`, `match`, `findInterval`, `cut(labels=)`, `split`, `tapply`, `rowsum`, `outer`. Build strings with `paste(x, collapse = "")`.
- `[[` errors on a bad index. `$` partial-matches on lists and fails on atomic vectors.
- Compare doubles with `isTRUE(all.equal(a, b))` (`seq(0, 1, 0.1)[4] == 0.3` is FALSE). `identical()` also compares names.
- `as.numeric(f)` gives factor codes; use `as.numeric(as.character(f))`.
- Rounding: `round(2.5)` is 2 and `round(0.125, 2)` is 0.12.
- `seq(as.Date("2026-01-31"), by = "month", length.out = 3)` gives Jan 31, **Mar 3**, Mar 31. Pass `tz=` explicitly to `format()`/`as.POSIXct()`.
- `max(numeric(0))` returns `-Inf` with a warning, so guard empty input.
- Inside functions, restore state: `old <- options(digits = 3); on.exit(options(old), add = TRUE)`. The same works for `par`/`setwd`. `on.exit()` does nothing at the top level of a script.
- Hash maps: `e <- new.env(hash = TRUE)`; `get0(k, e, inherits = FALSE)`.
- `parallel::mclapply(x, f, mc.cores = n)` forks (serial on Windows). `parLapply(makeCluster(n), x, f)` is portable; call `stopCluster()` when done.

## Conditions
```r
stop(errorCondition(sprintf("`x` must be numeric, not %s.", class(x)[1]),
                    class = "mypkg_bad_input", x = x))  # extra fields via ...: e$x
tryCatch(f(), mypkg_bad_input = function(e) conditionMessage(e))
withCallingHandlers(f(), warning = function(w) {
  message("note: ", conditionMessage(w)); invokeRestart("muffleWarning")
})
stopifnot("`n` must be positive" = n > 0)
```
- Write messages as "`x` must ..." or "Can't ...".
- Report progress with `message()`, not `cat`/`print`. Use `cli::cli_abort()` only if cli is already a dependency.

## Scripts and projects
```r
#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L) { message("usage: tool.R <n>"); quit(status = 2L) }
```
- Run with `Rscript --vanilla tool.R 5`.
- Store objects with `saveRDS`/`readRDS`, not `save`/`load`. Write CSVs with `write.csv(df, p, row.names = FALSE)`.
- Build paths with `file.path()`; use `tempfile(fileext = ".csv")` for scratch files.
- renv: `renv::init()`, then `renv::install("pkg")` and `renv::snapshot()`. Others run `renv::restore()`; check with `renv::status()`. Commit `renv.lock`, `.Rprofile`, `renv/activate.R` and `renv/settings.json`.

## Packages
Layout: `DESCRIPTION NAMESPACE LICENSE NEWS.md R/ man/ tests/testthat.R tests/testthat/test-<file>.R inst/ data/ src/ .Rbuildignore`.
- **DESCRIPTION**:
  - `Authors@R: person("A", "B", email = "...", role = c("aut", "cre", "cph"))`
  - `License: MIT + file LICENSE`; the LICENSE file holds `YEAR:` and `COPYRIGHT HOLDER:`
  - `Encoding: UTF-8` and `Config/testthat/edition: 3`
  - `Imports:` for runtime dependencies, `Suggests:` for test and optional ones
- **Dependencies**:
  - Every package used in tests (e.g. `withr::`) must be declared, or check WARNs "'::' or ':::' import not declared".
  - Guard optional packages with `requireNamespace("pkg", quietly = TRUE)`.
  - Never call `library()` in `R/`; use `pkg::fn` or `importFrom`.
- **NAMESPACE**: `export(f)`, `S3method(print, cls)`, `importFrom(stats, median)`. With roxygen2, use `#' @export` and run `devtools::document()`. Don't hand-edit generated `man/` or NAMESPACE.
- **Docs**: Rd for exported functions needs `\value{}` and runnable `\examples{}`. Use `\donttest{}` only for slow examples and `try()` for expected errors.
```sh
R CMD build mypkg
R CMD check --as-cran --no-manual mypkg_0.1.0.tar.gz
R CMD INSTALL -l ~/rlib mypkg_0.1.0.tar.gz    # --build makes a binary
```
- devtools: `load_all()`, `test()`, `document()`, `check()`.
- Format with `air format .` (`--check` in CI; config in `air.toml` `[format]`) and lint with `lintr::lint_package()`.

## testthat 3e (3.3.x)
- `tests/testthat.R` is just `library(testthat); library(pkg); test_check("pkg")`.
- Run with `testthat::test_local(".")`.
```r
test_that("robust", {
  expect_equal(f(c(1, 2, 100))$median, 2)            # has tolerance
  expect_equal(c(a = 1), 1, ignore_attr = TRUE)      # not expect_equivalent
  expect_error(f("a"), class = "mypkg_bad_input")    # match on class
  expect_snapshot(f("a"), error = TRUE)              # writes _snaps/<file>.md
  local_mocked_bindings(median = function(...) 42)   # not with_mock()
  withr::local_options(digits = 3)                   # reset after the test
  skip_if_not_installed("pkg")
})
```
- `describe()`/`it()` also work. Don't use `context()`.
- Read fixtures with `test_path("fixtures", "x.csv")`.
- `expect_snapshot()` and `skip_on_cran()` tests are **skipped under `R CMD check`** unless `NOT_CRAN=true`. Accept snapshot changes with `snapshot_accept()`.

## Errors and fixes
- `object of type 'closure' is not subsettable`: a function was indexed (e.g. `data[1]` with no `data` object). Define the variable.
- `$ operator is invalid for atomic vectors`: use `x[["a"]]`.
- `argument is of length zero` / `missing value where TRUE/FALSE needed`: `if()` got NULL or NA. Guard with `length(x) > 0` or `isTRUE()`.
- `the condition has length > 1`: use `any()`/`all()`, or `ifelse()`.
- `non-numeric argument to binary operator`: the data is character; convert with `as.numeric()` and check for NA.
- `replacement has 2 rows, data has 3`: column length mismatch.
- `names do not match previous names`: `rbind` of data frames with different columns.
- `values must be type 'double', but FUN(X[[1]]) result is type 'character'`: fix the `vapply` `FUN.VALUE`.
- `there is no package called 'x'`: install it or fix `.libPaths()`.
- check `no visible binding for global variable 'cyl'`: an NSE column name in package code. Use `.data$cyl` or `utils::globalVariables("cyl")`.
- check `code/documentation mismatches`: rerun `document()` so `\usage` matches the formals.
