(** Evaluator for 64-bit signed integer arithmetic expressions.

    Grammar:
    {v
    expr    := term    (('+' | '-') term)*
    term    := unary   (('*' | '/' | '%') unary)*
    unary   := '-' unary | primary
    primary := NUMBER | '(' expr ')'
    NUMBER  := [0-9]+
    v}
    Spaces and tabs may appear between tokens. *)

type error =
  | Syntax_error
  | Division_by_zero
  | Overflow

val eval : string -> (int64, error) result
(** [eval s] parses and evaluates [s] as a whole expression. *)

val is_blank : string -> bool
(** [is_blank s] is [true] when [s] holds only spaces and tabs. *)
