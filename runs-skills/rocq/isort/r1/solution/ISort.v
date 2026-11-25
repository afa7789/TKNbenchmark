(* Complete every proof. Do not change any definition or theorem statement. *)
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

(** Inserting into a sorted list keeps it sorted. *)
Lemma insert_sorted : forall x l, Sorted l -> Sorted (insert x l).
Proof.
  intros x l Hs.
  induction Hs as [| y | y z zs Hyz Hs IH]; cbn [insert].
  - constructor.
  - destruct (Nat.leb_spec x y); constructor; auto with arith; constructor.
  - destruct (Nat.leb_spec x y).
    + constructor; [assumption | constructor; assumption].
    + cbn [insert] in IH |- *.
      destruct (Nat.leb_spec x z); constructor; auto with arith.
Qed.

Theorem isort_sorted : forall l, Sorted (isort l).
Proof.
  induction l as [| x xs IH]; cbn [isort].
  - constructor.
  - apply insert_sorted, IH.
Qed.

(** [insert x] adds exactly one occurrence of [x]. *)
Lemma insert_count : forall n x l,
  count n (insert x l) = (if Nat.eqb x n then 1 else 0) + count n l.
Proof.
  intros n x l.
  induction l as [| y ys IH]; cbn [insert count].
  - reflexivity.
  - destruct (Nat.leb x y); cbn [count].
    + reflexivity.
    + rewrite IH. lia.
Qed.

Theorem isort_count : forall n l, count n (isort l) = count n l.
Proof.
  intros n l.
  induction l as [| x xs IH]; cbn [isort count].
  - reflexivity.
  - rewrite insert_count, IH. reflexivity.
Qed.
