# Sources

- https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/9.14.1-notes.html: the 9.14.1 language, warning and library changes. Covers `-Wincomplete-record-selectors` in `-Wall`, `TypeAbstractions`, `DataKinds` enforcement, the `setField` flip, the `SPECIALISE` deprecation, multi-home-unit GHCi, and the boot package versions.
- https://www.haskell.org/ghc/blog/20251219-ghc-9.14.1-released.html: release announcement, with highlights and the `-fpolymorphic-specialisation` default.
- https://discourse.haskell.org/t/ghc-9-14-1-is-now-available/13430: release announcement, plus the statement that 9.14 is the first LTS.
- https://minoki.github.io/posts/2025-08-31-whats-new-in-ghc-9-14.html: walkthrough of 9.14 features. Source for `Data.Enum.enumerate`, `HasCallStack` on `fail`, `data` in import lists, and `--enable-multi-repl`.
- https://hackage.haskell.org/package/base-4.22.0.0/changelog: base 4.20–4.22 API additions and removals (`foldl'` in Prelude, `inits1`/`tails1`, `compareLength`, binary-literal `read`, exception display).
- https://hackage.haskell.org/package/containers-0.8/changelog: containers 0.7/0.8 changes (`filterKeys`, `symmetricDifference`, `NECyclicSCC`).
- https://hackage.haskell.org/package/mtl-2.3.1/changelog: mtl 2.3 stopped re-exporting `Control.Monad`.
- https://hackage.haskell.org/package/text-2.1.3/changelog: text 2.x UTF-8 representation, `Data.Text.IO.Utf8`, and `T.show`.
- https://downloads.haskell.org/ghc/9.14.1/docs/users_guide/exts/control.html: the default edition is GHC2021, the GHC2024 extension list, and the advice to declare the edition explicitly.
- https://cabal.readthedocs.io/en/stable/getting-started.html: cabal init/build/run workflow and the script header format.
- https://blog.haskell.org/cabal-3-16-0-0-release/: Cabal 3.16 release context for the 9.14 toolchain.
- https://kowainik.github.io/posts/2019-02-06-style-guide: Kowainik style guide. Source for the warning set (`-Wcompat`, `-Wpartial-fields`, `-Wmissing-deriving-strategies`), deriving strategies, strict fields and explicit exports.
- https://github.com/tibbe/haskell-style-guide/blob/master/haskell-style.md: Johan Tibell's style guide. Strict fields with lazy functions, import grouping, and `-Wall` cleanliness.
- https://github.com/mightybyte/haskell-skill (haskell-coder/SKILL.md): a published Haskell agent skill. Common warnings stanza, a thin exe over the library, `Text` over `String`, strict folds, mtl and MonadFail pitfalls, and testing with hspec/QuickCheck.
- https://www.skillsdirectory.com/skills/modbender-haskell: a second published Haskell skill. Agrees on avoiding partial functions, `Either` for expected errors, and strictness habits.
- https://dev.to/olivia_craft/claudemd-for-haskell-13-rules-that-make-ai-write-idiomatic-type-safe-haskell-1l4n: a CLAUDE.md rule set for Haskell. Pin the edition, total functions, newtypes, `Text`, hspec plus QuickCheck.
- https://github.com/tonyday567/checklist: a practitioner checklist for project setup and CI (cabal, hlint, ormolu, haskell-actions).

All commands, APIs, flags and error codes in SKILL.md were checked locally against GHC 9.14.1 and cabal-install 3.18.2.0 on macOS arm64.
