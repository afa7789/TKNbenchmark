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
}

lemma AppendAssoc<T>(xs: List<T>, ys: List<T>, zs: List<T>)
  ensures Append(Append(xs, ys), zs) == Append(xs, Append(ys, zs))
{
}

lemma RevAppend<T>(xs: List<T>, ys: List<T>)
  ensures Rev(Append(xs, ys)) == Append(Rev(ys), Rev(xs))
{
  match xs
  case Nil => AppendNil(Rev(ys));
  case Cons(x, rest) =>
    RevAppend(rest, ys);
    AppendAssoc(Rev(ys), Rev(rest), Cons(x, Nil));
}

lemma RevRev<T>(xs: List<T>)
  ensures Rev(Rev(xs)) == xs
{
  match xs
  case Nil =>
  case Cons(x, rest) =>
    RevAppend(Rev(rest), Cons(x, Nil));
    RevRev(rest);
}
