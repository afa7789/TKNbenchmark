-- Complete every proof. Do not change any definition or theorem statement.
namespace TKN

def insert (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insert x ys

def isort : List Nat → List Nat
  | [] => []
  | x :: xs => insert x (isort xs)

inductive Sorted : List Nat → Prop
  | nil : Sorted []
  | single (x : Nat) : Sorted [x]
  | cons (x y : Nat) (ys : List Nat) : x ≤ y → Sorted (y :: ys) → Sorted (x :: y :: ys)

def count (n : Nat) : List Nat → Nat
  | [] => 0
  | x :: xs => (if x = n then 1 else 0) + count n xs

/-- Inserting into a sorted list keeps it sorted. -/
theorem insert_sorted (x : Nat) {l : List Nat} (h : Sorted l) : Sorted (insert x l) := by
  induction h with
  | nil => exact Sorted.single x
  | single y =>
    unfold insert
    split
    · exact Sorted.cons x y [] ‹_› (Sorted.single y)
    · exact Sorted.cons y x [] (by omega) (Sorted.single x)
  | cons y z zs hyz hs ih =>
    unfold insert
    split
    · exact Sorted.cons x y _ ‹_› (Sorted.cons y z zs hyz hs)
    · rename_i hxy
      unfold insert at ih ⊢
      split
      · exact Sorted.cons y x _ (by omega) (Sorted.cons x z zs ‹_› hs)
      · rename_i hxz
        rw [if_neg hxz] at ih
        exact Sorted.cons y z _ hyz ih

/-- Inserting `x` adds one occurrence of `x` and leaves other counts unchanged. -/
theorem count_insert (n x : Nat) (l : List Nat) :
    count n (insert x l) = (if x = n then 1 else 0) + count n l := by
  induction l with
  | nil => rfl
  | cons y ys ih =>
    unfold insert
    split
    · rfl
    · simp only [count, ih]
      omega

theorem isort_sorted (xs : List Nat) : Sorted (isort xs) := by
  induction xs with
  | nil => exact Sorted.nil
  | cons x xs ih => exact insert_sorted x ih

theorem isort_count (n : Nat) (xs : List Nat) : count n (isort xs) = count n xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp only [isort, count, count_insert, ih]

end TKN
