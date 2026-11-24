// Complete every proof. Do not change any definition or lemma statement.
datatype List<T> = Nil | Cons(head: T, tail: List<T>)

function Append<T>(xs: List<T>, ys: List<T>): List<T>
{
  match xs
  case Nil => ys
  case Cons(x, rest) => Cons(x, Append(rest, ys))
}

function Rev<T>(xs: List<T>): List<T>
{
  match xs
  case Nil => Nil
  case Cons(x, rest) => Append(Rev(rest), Cons(x, Nil))
}

lemma AppendNil<T>(xs: List<T>)
  ensures Append(xs, Nil) == xs
{
  assume false;
}

lemma AppendAssoc<T>(xs: List<T>, ys: List<T>, zs: List<T>)
  ensures Append(Append(xs, ys), zs) == Append(xs, Append(ys, zs))
{
  assume false;
}

lemma RevAppend<T>(xs: List<T>, ys: List<T>)
  ensures Rev(Append(xs, ys)) == Append(Rev(ys), Rev(xs))
{
  assume false;
}

lemma RevRev<T>(xs: List<T>)
  ensures Rev(Rev(xs)) == xs
{
  assume false;
}
