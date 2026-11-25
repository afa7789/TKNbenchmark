(* Complete every proof. Do not change any definition or theorem statement. *)
Fixpoint append {A : Type} (xs ys : list A) : list A :=
  match xs with
  | nil => ys
  | cons x xs' => cons x (append xs' ys)
  end.

Fixpoint rev {A : Type} (xs : list A) : list A :=
  match xs with
  | nil => nil
  | cons x xs' => append (rev xs') (cons x nil)
  end.

Theorem append_nil : forall (A : Type) (xs : list A), append xs nil = xs.
Proof.
  intros A xs.
  induction xs as [| x xs IH]; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.

Theorem append_assoc : forall (A : Type) (xs ys zs : list A),
  append (append xs ys) zs = append xs (append ys zs).
Proof.
  intros A xs ys zs.
  induction xs as [| x xs IH]; simpl.
  - reflexivity.
  - rewrite IH. reflexivity.
Qed.

Theorem rev_append : forall (A : Type) (xs ys : list A),
  rev (append xs ys) = append (rev ys) (rev xs).
Proof.
  intros A xs ys.
  induction xs as [| x xs IH]; simpl.
  - rewrite append_nil. reflexivity.
  - rewrite IH, append_assoc. reflexivity.
Qed.

Theorem rev_rev : forall (A : Type) (xs : list A), rev (rev xs) = xs.
Proof.
  intros A xs.
  induction xs as [| x xs IH]; simpl.
  - reflexivity.
  - rewrite rev_append, IH. reflexivity.
Qed.
