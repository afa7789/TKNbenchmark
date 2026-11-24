// Complete every proof. Do not change any definition or lemma statement.
datatype List = Nil | Cons(head: nat, tail: List)

function Insert(x: nat, xs: List): List
{
  match xs
  case Nil => Cons(x, Nil)
  case Cons(y, rest) => if x <= y then Cons(x, xs) else Cons(y, Insert(x, rest))
}

function ISort(xs: List): List
{
  match xs
  case Nil => Nil
  case Cons(x, rest) => Insert(x, ISort(rest))
}

predicate Sorted(xs: List)
{
  match xs
  case Nil => true
  case Cons(x, rest) =>
    match rest
    case Nil => true
    case Cons(y, _) => x <= y && Sorted(rest)
}

function Count(n: nat, xs: List): nat
{
  match xs
  case Nil => 0
  case Cons(x, rest) => (if x == n then 1 else 0) + Count(n, rest)
}

// The head of `Insert(x, xs)` is either `x` or the head of `xs`.
lemma InsertHead(x: nat, xs: List)
  ensures Insert(x, xs).head == x || (xs.Cons? && Insert(x, xs).head == xs.head)
{
}

// Inserting into a sorted list yields a sorted list.
lemma InsertSorted(x: nat, xs: List)
  requires Sorted(xs)
  ensures Sorted(Insert(x, xs))
{
  match xs
  case Nil =>
  case Cons(y, rest) =>
    if x > y {
      InsertSorted(x, rest);
      InsertHead(x, rest);
    }
}

lemma ISortSorted(xs: List)
  ensures Sorted(ISort(xs))
{
  match xs
  case Nil =>
  case Cons(x, rest) =>
    ISortSorted(rest);
    InsertSorted(x, ISort(rest));
}

// Inserting `x` adds exactly one occurrence of `x` and leaves other counts unchanged.
lemma InsertCount(n: nat, x: nat, xs: List)
  ensures Count(n, Insert(x, xs)) == (if x == n then 1 else 0) + Count(n, xs)
{
  match xs
  case Nil =>
  case Cons(y, rest) =>
    if x > y {
      InsertCount(n, x, rest);
    }
}

lemma ISortCount(n: nat, xs: List)
  ensures Count(n, ISort(xs)) == Count(n, xs)
{
  match xs
  case Nil =>
  case Cons(x, rest) =>
    ISortCount(n, rest);
    InsertCount(n, x, ISort(rest));
}
