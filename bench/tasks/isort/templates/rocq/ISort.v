(* Complete every proof. Do not change any definition or theorem statement. *)
Fixpoint insert (x : nat) (l : list nat) : list nat :=
  match l with
  | nil => cons x nil
  | cons y ys => if Nat.leb x y then cons x (cons y ys) else cons y (insert x ys)
  end.

Fixpoint isort (l : list nat) : list nat :=
  match l with
  | nil => nil
  | cons x xs => insert x (isort xs)
  end.

Inductive Sorted : list nat -> Prop :=
  | sorted_nil : Sorted nil
  | sorted_single : forall x, Sorted (cons x nil)
  | sorted_cons : forall x y ys, x <= y -> Sorted (cons y ys) -> Sorted (cons x (cons y ys)).

Fixpoint count (n : nat) (l : list nat) : nat :=
  match l with
  | nil => 0
  | cons x xs => (if Nat.eqb x n then 1 else 0) + count n xs
  end.

Theorem isort_sorted : forall l, Sorted (isort l).
Proof.
Admitted.

Theorem isort_count : forall n l, count n (isort l) = count n l.
Proof.
Admitted.
