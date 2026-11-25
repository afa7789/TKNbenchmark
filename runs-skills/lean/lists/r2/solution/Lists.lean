-- Complete every proof. Do not change any definition or theorem statement.
namespace TKN

def append {α : Type} : List α → List α → List α
  | [], ys => ys
  | x :: xs, ys => x :: append xs ys

def rev {α : Type} : List α → List α
  | [] => []
  | x :: xs => append (rev xs) [x]

theorem append_nil {α : Type} (xs : List α) : append xs [] = xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp [append, ih]

theorem append_assoc {α : Type} (xs ys zs : List α) :
    append (append xs ys) zs = append xs (append ys zs) := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp [append, ih]

theorem rev_append {α : Type} (xs ys : List α) :
    rev (append xs ys) = append (rev ys) (rev xs) := by
  induction xs with
  | nil => simp [append, rev, append_nil]
  | cons x xs ih => simp [append, rev, ih, append_assoc]

theorem rev_rev {α : Type} (xs : List α) : rev (rev xs) = xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp [rev, rev_append, ih, append]

end TKN
