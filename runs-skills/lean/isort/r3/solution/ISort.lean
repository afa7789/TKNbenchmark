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
    by_cases hxy : x ≤ y
    · simp only [insert, hxy, if_true]
      exact .cons x y [] hxy (.single y)
    · simp only [insert, hxy, if_false]
      exact .cons y x [] (by omega) (.single x)
  | cons y z zs hyz _ ih =>
    by_cases hxy : x ≤ y
    · simp only [insert, hxy, if_true]
      exact .cons x y (z :: zs) hxy (.cons y z zs hyz ‹_›)
    · simp only [insert, hxy, if_false]
      by_cases hxz : x ≤ z
      · simp only [insert, hxz, if_true] at ih ⊢
        exact .cons y x (z :: zs) (by omega) ih
      · simp only [insert, hxz, if_false] at ih ⊢
        exact .cons y z (insert x zs) hyz ih

/-- Inserting `x` adds exactly one occurrence of `x`. -/
theorem count_insert (n x : Nat) (l : List Nat) :
    count n (insert x l) = (if x = n then 1 else 0) + count n l := by
  induction l with
  | nil => simp [insert, count]
  | cons y ys ih =>
    by_cases hxy : x ≤ y
    · simp [insert, hxy, count]
    · simp only [insert, hxy, if_false, count, ih]
      omega

theorem isort_sorted (xs : List Nat) : Sorted (isort xs) := by
  induction xs with
  | nil => exact .nil
  | cons x xs ih => exact insert_sorted x ih

theorem isort_count (n : Nat) (xs : List Nat) : count n (isort xs) = count n xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp only [isort, count_insert, ih, count]

end TKN
