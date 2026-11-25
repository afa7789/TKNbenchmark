---
name: haskell
description: "Version-correct, idiomatic Haskell for the installed toolchain (The Glorious Glasgow Haskell Compilation System, version 9.14.1): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Haskell code."
---

# Haskell with GHC 9.14.1 (base 4.22, cabal-install 3.18)

GHC 9.14 is the first LTS. Boot packages need no download: base-4.22, containers-0.8, text-2.1.3, bytestring-0.12, mtl-2.3.1, transformers-0.6, stm, deepseq, array, directory, filepath-1.5, process, time-1.15. Build with cabal and never use the `v1-` commands.

## Layout and .cabal
`pkg.cabal cabal.project src/Pkg.hs src/Pkg/Internal.hs app/Main.hs test/Spec.hs`
```cabal
cabal-version:   3.4
name:            pkg
version:         0.1.0.0

common common
    default-language: GHC2024
    ghc-options: -Wall -Wcompat -Widentities -Wredundant-constraints
                 -Wpartial-fields -Wmissing-deriving-strategies -Wunused-packages
    build-depends: base ^>=4.22

library
    import:          common
    hs-source-dirs:  src
    exposed-modules: Pkg
    other-modules:   Pkg.Internal
    build-depends:   containers ^>=0.8, text ^>=2.1

executable pkg
    import:         common
    hs-source-dirs: app
    main-is:        Main.hs
    ghc-options:    -threaded -rtsopts "-with-rtsopts=-N"
    build-depends:  pkg, text

test-suite pkg-test
    import:         common
    type:           exitcode-stdio-1.0
    hs-source-dirs: test
    main-is:        Spec.hs
    build-depends:  pkg, hspec >=2.11 && <3, QuickCheck >=2.14 && <3
```
- **List every module.** Each one must appear in `exposed-modules` or `other-modules`, otherwise you get GHC-32850 `-Wmissing-home-modules` and link errors.
- **List every imported package** in each component's `build-depends`, tests included. A missing one gives GHC-87110 "member of the hidden package".
- **Pin the edition.** Plain `ghc`/`ghci` default to **GHC2021**, which lacks `LambdaCase`, `DerivingStrategies`, `GADTs` and `DataKinds`. Pass `-XGHC2024` when not using cabal.
- **GHC2024 already includes** `ImportQualifiedPost` (`import Data.Map.Strict qualified as Map`), `TypeApplications`, `ScopedTypeVariables`, `BangPatterns`, `NamedFieldPuns` and `TupleSections`. Enable `OverloadedStrings`, `RecordWildCards`, `DerivingVia`, `DeriveAnyClass` and `OverloadedRecordDot` per file.
- **The RTS is non-threaded unless you link with `-threaded`.**

`cabal.project`:
```
packages: .
tests: True              -- `cabal build all` now builds tests too
package pkg
  ghc-options: -Werror   -- local only; keep -Werror out of a published .cabal
```

## Commands (verified)
```sh
cabal update                                   # refresh the Hackage index
cabal build all                                # tests only with tests: True or --enable-tests
cabal run -v0 pkg -- args < in.txt
cabal test --test-show-details=direct --test-options='-m "substring"'
cabal repl lib:pkg                             # :r :t :i
cabal repl --enable-multi-repl lib:pkg exe:pkg # new in 9.14
cabal build -O2 exe:pkg ; cabal list-bin pkg
cabal install exe:pkg --installdir=./bin --install-method=copy --overwrite-policy=always
cabal run --enable-profiling --profiling-detail=late pkg -- +RTS -p -s   # pkg.prof
cabal freeze ; cabal outdated ; cabal gen-bounds ; cabal check ; cabal sdist ; cabal haddock
ghc -XGHC2024 -O2 -Wall -outputdir /tmp/o -o app Main.hs   # -fno-code = typecheck only
```
For a script, use the header below, then `cabal run script.hs` (or `chmod +x` it):
```haskell
#!/usr/bin/env cabal
{- cabal:
build-depends: base, containers
default-language: GHC2024
-}
```

## Changes that break code in 9.10–9.14
- **`-Wincomplete-record-selectors` is now in `-Wall`.** `radius s` on `Circle {radius} | Square {side}` warns, and fails under `-Werror`. Pattern match instead, or keep field names off sum types.
- **`f (MkT @a x)` needs `{-# LANGUAGE TypeAbstractions #-}`** (GHC-78249).
- **Using a data type as a kind needs `DataKinds`.**
- **`setField` now takes the value first:** `a -> r -> r` (`OverloadedRecordUpdate`).
- **In import/export lists, write `data` instead of `pattern`**, which now triggers `-Wpattern-namespace-specifier`.
- **The multi-type `SPECIALISE` form is deprecated.** Use `{-# SPECIALISE f @Int #-}`, one pragma per type.
- **The Prelude exports `foldl'`.** `import Data.List (foldl')` now gives a redundant-import warning.
- **`head` and `tail` raise `-Wx-partial`.** Use patterns, `uncons`, `unsnoc`, `(!?)` or `NonEmpty`. `last`, `init`, `!!` and `fromJust` don't warn but are still partial.
- **mtl 2.3 no longer re-exports `Control.Monad`.** Import `forM_` and `when` from it directly, otherwise you get GHC-88464 "not in scope".
- **`fail` now has `HasCallStack`.** Uncaught exceptions print a "HasCallStack backtrace:" block.
- **containers 0.8:** new `Map.filterKeys` and `Set.symmetricDifference`. `CyclicSCC` is now a pattern synonym for `NECyclicSCC (NonEmpty v)`.

## Newer APIs (verified)
```haskell
import Data.Enum (enumerate)                 -- base 4.22
import Data.List (unsnoc, (!?), inits1)      -- 4.19 / 4.21
enumerate @Color                             -- all values; needs Enum, Bounded
unsnoc [1,2,3] == Just ([1,2],3); [1,2] !? 5 == Nothing
Data.Text.show (42 :: Int)                   -- Text directly (text >= 2.1.2)
Data.List.NonEmpty.compareLength xs 3        -- LT | EQ | GT
readMaybe "0b101" :: Maybe Int               -- Just 5
```
`MultilineStrings` (`"""…"""`) strips common indentation and the final newline.

## Correct and fast idioms
- **Text:** use `Text`/`ByteString`, not `String`. `Data.Text.IO` decodes with the locale. Use `Data.Text.IO.Utf8` or `hSetEncoding h utf8` so a C locale in Linux CI doesn't break decoding.
- **Fast numeric input:** `map (maybe 0 fst . BS.readInt) . BS.words <$> BS.getContents` (Char8). For Text, use `Data.Text.Read.decimal :: Text -> Either String (Int, Text)`.
- **Strictness:** use `Data.Map.Strict`, `foldl'`, `modify'`, `modifyIORef'`, `atomicModifyIORef'`, `modifySTRef'`, `modifyTVar'` and strict fields (`!Int`). Lazy accumulators leak space.
- **Arrays:** use `runSTUArray` with `newArray`/`readArray`/`writeArray` (`Data.Array.ST`), then index the `UArray` with `(!)`. Use `runST` with an `STRef` for local mutation.
- **Counting and sorting:** `Map.fromListWith (+)` or `Map.insertWith (+) k 1`, and `sortOn (Down . snd)`.
- **Concurrency:** use `stm` (`newTVarIO`, `atomically`) and `MVar`. `async` is not a boot package, so add it to the deps. Build with `-threaded` and run with `+RTS -N`.
- **Exceptions:** `data E = … deriving stock Show` plus `instance Exception E`. Use `throwIO` in IO, `try @E`, `catch` with a typed lambda `\(e :: E) ->`, and `bracket`/`finally`. Wrap pure code in `evaluate` before `try`.
- **Deriving:** `deriving stock (Show, Generic)`, `deriving anyclass NFData`, `deriving (Semigroup, Monoid) via (Sum Int)`.
- **Records:** with `DuplicateRecordFields` a bare selector is ambiguous (GHC-87543). Use `OverloadedRecordDot` (`u.name`) or prefixed field names.
- **Expected failures:** use `Maybe`/`Either`/`readMaybe`. Keep `error` and `undefined` out of libraries.

## Errors and fixes
- **GHC-87139 `Illegal deriving strategy`:** the module is on GHC2021. Set `default-language: GHC2024`.
- **GHC-39999 `No instance for (Num a)`:** add the constraint to the signature, or annotate the literal.
- **Ambiguous `IsString` with `OverloadedStrings`:** annotate `("x" :: Text)`.
- **`Pattern match failure in 'do' block`:** a refutable `[a,b] <- …` failed. Use `case`.
- **`Could not find module` in the REPL:** name the component, e.g. `cabal repl test:pkg-test`.
- **`<<loop>>` or a heap overflow:** a self-referential `let` or a lazy accumulator. Check with `+RTS -s`.
