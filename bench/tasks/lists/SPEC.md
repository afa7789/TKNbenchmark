# lists — prove four lemmas about lists

The file next to this spec (`Lists.lean`, `Lists.v` or `Lists.dfy`, depending on your language)
defines list append and reverse from scratch and states four theorems:

1. appending the empty list is the identity;
2. append is associative;
3. reversing an append swaps and reverses the parts: `rev (xs ++ ys) = rev ys ++ rev xs`;
4. reversing twice gives back the original list.

Replace every placeholder proof (`sorry`, `Admitted.`, `assume false;`) with a real proof. You may add
helper lemmas. You may not change the definitions or the statements, add axioms, or use escape
hatches. Only the language's standard library is available.

Acceptance: the file is accepted by the language's checker (`lean`, `coqc`, `dafny verify`), contains
no escape hatches, and every definition and statement is unchanged.
