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

lemma ISortSorted(xs: List)
  ensures Sorted(ISort(xs))
{
  assume false;
}

lemma ISortCount(n: nat, xs: List)
  ensures Count(n, ISort(xs)) == Count(n, xs)
{
  assume false;
}
