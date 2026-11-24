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
  | nil => exact .single x
  | single y =>
    unfold insert
    split
    · exact .cons x y [] ‹_› (.single y)
    · exact .cons y x [] (by omega) (.single x)
  | cons y z zs hyz hs ih =>
    unfold insert
    split
    · exact .cons x y (z :: zs) ‹_› (.cons y z zs hyz hs)
    · rename_i hxy
      unfold insert at ih ⊢
      split
      · exact .cons y x (z :: zs) (by omega) (by simpa [*] using ih)
      · exact .cons y z (insert x zs) hyz (by simpa [*] using ih)

theorem isort_sorted (xs : List Nat) : Sorted (isort xs) := by
  induction xs with
  | nil => exact .nil
  | cons x xs ih => exact insert_sorted x ih

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

theorem isort_count (n : Nat) (xs : List Nat) : count n (isort xs) = count n xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp only [isort, count, count_insert, ih]

end TKN
