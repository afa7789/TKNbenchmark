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

lemma InsertSorted(x: nat, xs: List)
  requires Sorted(xs)
  ensures Sorted(Insert(x, xs))
{
  match xs
  case Nil =>
  case Cons(y, rest) =>
    if x > y {
      InsertSorted(x, rest);
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

lemma CountInsert(n: nat, x: nat, xs: List)
  ensures Count(n, Insert(x, xs)) == (if x == n then 1 else 0) + Count(n, xs)
{
  match xs
  case Nil =>
  case Cons(y, rest) =>
    if x > y {
      CountInsert(n, x, rest);
    }
}

lemma ISortCount(n: nat, xs: List)
  ensures Count(n, ISort(xs)) == Count(n, xs)
{
  match xs
  case Nil =>
  case Cons(x, rest) =>
    ISortCount(n, rest);
    CountInsert(n, x, ISort(rest));
}
