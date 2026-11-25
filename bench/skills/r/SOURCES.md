# Sources

- Installed `R_HOME/doc/NEWS` (R 4.6.2, `/opt/homebrew/Cellar/r/4.6.2/lib/R/doc/NEWS`): the 4.6.2/4.6.1/4.6.0/4.5.0/4.4.0 changes: new base functions, defunct items, C++20 default, non-API C entry points.
- https://cran.r-project.org/doc/manuals/r-release/NEWS.html: the official online NEWS, used to cross-check the local file.
- https://www.jumpingrivers.com/blog/whats-new-r46/: R 4.6.0 highlights with examples (`%notin%`, `summary(<chr>)`, `list.files(fixed=)`).
- https://www.r-bloggers.com/2026/04/whats-new-in-r-4-6-0/: a second summary of the 4.6.0 features.
- https://style.tidyverse.org/ (syntax chapter): snake_case, `<-`, double quotes, `TRUE`/`FALSE`, `&&` in `if`, 80-column lines.
- https://github.com/posit-dev/skills: Posit's published agent skills (r-lib category); the index of R skills.
- https://raw.githubusercontent.com/posit-dev/skills/main/r-lib/r-package-development/SKILL.md: the devtools workflow, `air format .`, `|>` and `\(x)` rules, test file mapping.
- https://raw.githubusercontent.com/posit-dev/skills/main/r-lib/r-testthat/SKILL.md: testthat 3e setup, deprecated functions (`context`, `expect_equivalent`, `with_mock`), withr `local_*`, snapshots.
- https://raw.githubusercontent.com/posit-dev/skills/main/r-lib/r-tidyverse-style/SKILL.md: error-message wording ("must"/"Can't"), not mass-converting `%>%`, `return()` only for early exits.
- https://raw.githubusercontent.com/posit-dev/skills/main/r-lib/r-cran-extrachecks/SKILL.md: CRAN rules (`\value` and runnable examples, the `cph` role, `\donttest`).
- https://gist.github.com/sj-io/3828d64d0969f2a0f05297e59e6c15ad: a community CLAUDE.md ("Claude R Tidyverse Expert"): native pipe, preallocation, no `eval(parse())`, keep dependencies minimal.
- https://git.web.rug.nl/P281424/AMR/src/branch/gh-pages/CLAUDE.md: a real package's CLAUDE.md: Suggests plus `requireNamespace()`, never hand-edit `man/`, `devtools::check()`.
- https://www.r-bloggers.com/2026/03/a-few-claude-skills-for-r-users/: an overview of the published R skills and where they agree.
- https://r-pkgs.org/testing-basics.html: `tests/testthat.R` layout (don't edit it), edition 3 in DESCRIPTION, snapshots skipped on CRAN.
- https://rstudio.github.io/renv/articles/renv.html: the renv init/snapshot/restore/install workflow and which files to commit.
- https://posit-dev.github.io/air/ , https://posit-dev.github.io/air/cli.html , https://posit-dev.github.io/air/configuration.html: the Air formatter CLI (`air format .`, `--check`) and `air.toml` `[format]` keys.

All APIs, commands and flags in SKILL.md were checked against the installed R 4.6.2. Scratch snippets were run with Rscript, and a throwaway package went through `R CMD build`/`check`/`testthat::test_local` with testthat 3.3.2, withr 3.0.3, renv 1.3.1, lintr 3.4.0 and S7 1.0.0, installed into a temporary library that was then deleted.
