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

theorem insert_sorted (x : Nat) : ∀ l, Sorted l → Sorted (insert x l) := by
  intro l h
  induction h with
  | nil => exact Sorted.single x
  | single y =>
    by_cases hxy : x ≤ y
    · simp [insert, hxy]; exact Sorted.cons x y [] hxy (Sorted.single y)
    · simp [insert, hxy]; exact Sorted.cons y x [] (by omega) (Sorted.single x)
  | cons y z zs hyz hs ih =>
    by_cases hxy : x ≤ y
    · simp [insert, hxy]; exact Sorted.cons x y (z :: zs) hxy (Sorted.cons y z zs hyz hs)
    · by_cases hxz : x ≤ z
      · simp [insert, hxy, hxz] at ih ⊢
        exact Sorted.cons y x (z :: zs) (by omega) ih
      · simp [insert, hxy, hxz] at ih ⊢
        exact Sorted.cons y z (insert x zs) hyz ih

theorem isort_sorted (xs : List Nat) : Sorted (isort xs) := by
  induction xs with
  | nil => exact Sorted.nil
  | cons x xs ih => exact insert_sorted x (isort xs) ih

theorem count_insert (n x : Nat) (l : List Nat) :
    count n (insert x l) = (if x = n then 1 else 0) + count n l := by
  induction l with
  | nil => simp [insert, count]
  | cons y ys ih =>
    by_cases hxy : x ≤ y
    · simp [insert, hxy, count]
    · simp [insert, hxy, count, ih]; omega

theorem isort_count (n : Nat) (xs : List Nat) : count n (isort xs) = count n xs := by
  induction xs with
  | nil => rfl
  | cons x xs ih => simp [isort, count, count_insert, ih]

end TKN
