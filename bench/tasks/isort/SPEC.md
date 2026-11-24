# isort — prove insertion sort correct

The file next to this spec (`ISort.lean`, `ISort.v` or `ISort.dfy`, depending on your language)
defines insertion sort on lists of natural numbers, a `Sorted` predicate and a `count` function, and
states two theorems:

1. `isort xs` is sorted;
2. for every `n`, `isort xs` contains `n` exactly as many times as `xs` (it is a permutation).

Replace every placeholder proof (`sorry`, `Admitted.`, `assume false;`) with a real proof. You may add
helper lemmas. You may not change the definitions or the statements, add axioms, or use escape
hatches. Only the language's standard library is available.

Acceptance: the file is accepted by the language's checker (`lean`, `coqc`, `dafny verify`), contains
no escape hatches, and every definition and statement is unchanged.
