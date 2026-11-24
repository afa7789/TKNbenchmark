From Stdlib Require Import Arith Lia.

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

Lemma insert_sorted : forall x l, Sorted l -> Sorted (insert x l).
Proof.
  intros x l H. induction H as [| y | y z zs Hyz Hs IH]; simpl.
  - constructor.
  - destruct (Nat.leb x y) eqn:E.
    + apply Nat.leb_le in E. constructor; [assumption | constructor].
    + apply Nat.leb_gt in E. constructor; [lia | constructor].
  - destruct (Nat.leb x y) eqn:E.
    + apply Nat.leb_le in E. constructor; [assumption | constructor; assumption].
    + apply Nat.leb_gt in E. simpl in IH. destruct (Nat.leb x z) eqn:F.
      * apply Nat.leb_le in F. constructor; [lia | assumption].
      * constructor; assumption.
Qed.

Theorem isort_sorted : forall l, Sorted (isort l).
Proof.
  induction l as [| x xs IH]; simpl.
  - constructor.
  - apply insert_sorted. assumption.
Qed.

Lemma count_insert : forall n x l,
  count n (insert x l) = (if Nat.eqb x n then 1 else 0) + count n l.
Proof.
  intros n x l. induction l as [| y ys IH]; simpl.
  - reflexivity.
  - destruct (Nat.leb x y); simpl.
    + reflexivity.
    + rewrite IH. lia.
Qed.

Theorem isort_count : forall n l, count n (isort l) = count n l.
Proof.
  intros n l. induction l as [| x xs IH]; simpl.
  - reflexivity.
  - rewrite count_insert. rewrite IH. reflexivity.
Qed.
