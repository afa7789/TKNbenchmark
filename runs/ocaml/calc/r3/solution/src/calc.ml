(* Evaluator for 64-bit signed integer arithmetic expressions.

   Grammar:
     expr    := term    (('+' | '-') term)*
     term    := unary   (('*' | '/' | '%') unary)*
     unary   := '-' unary | primary
     primary := NUMBER | '(' expr ')'

   The expression is evaluated directly during recursive-descent parsing.
   Any syntax error, division by zero or overflow aborts evaluation. *)

exception Error

let fail () = raise_notrace Error

(* ---- Checked 64-bit arithmetic ---- *)

let add a b =
  let r = Int64.add a b in
  (* Overflow iff both operands share a sign that differs from the result. *)
  if Int64.logand (Int64.logxor a r) (Int64.logxor b r) < 0L then fail ();
  r

let sub a b =
  let r = Int64.sub a b in
  (* Overflow iff operands differ in sign and the result's sign differs from [a]. *)
  if Int64.logand (Int64.logxor a b) (Int64.logxor a r) < 0L then fail ();
  r

let neg a = if a = Int64.min_int then fail () else Int64.neg a

let mul a b =
  if a = 0L || b = 0L then 0L
  else if (a = -1L && b = Int64.min_int) || (b = -1L && a = Int64.min_int) then
    fail ()
  else
    let r = Int64.mul a b in
    if Int64.div r b <> a then fail ();
    r

let div a b =
  if b = 0L then fail ()
  else if b = -1L then neg a
  else Int64.div a b

let rem a b =
  if b = 0L then fail ()
  else if b = -1L then 0L
  else Int64.rem a b

(* ---- Parser / evaluator ---- *)

type state = { src : string; mutable pos : int }

let is_blank = function ' ' | '\t' -> true | _ -> false
let is_digit = function '0' .. '9' -> true | _ -> false

let skip_blanks st =
  let len = String.length st.src in
  while st.pos < len && is_blank st.src.[st.pos] do
    st.pos <- st.pos + 1
  done

(* Next non-blank character, without consuming it. *)
let peek st =
  skip_blanks st;
  if st.pos < String.length st.src then Some st.src.[st.pos] else None

let advance st = st.pos <- st.pos + 1

let number st =
  let len = String.length st.src in
  let limit = Int64.div Int64.max_int 10L in
  let last = Int64.rem Int64.max_int 10L in
  let rec loop acc =
    if st.pos < len && is_digit st.src.[st.pos] then begin
      let d = Int64.of_int (Char.code st.src.[st.pos] - Char.code '0') in
      if acc > limit || (acc = limit && d > last) then fail ();
      advance st;
      loop (Int64.add (Int64.mul acc 10L) d)
    end
    else acc
  in
  loop 0L

let rec expr st =
  let rec loop acc =
    match peek st with
    | Some '+' -> advance st; loop (add acc (term st))
    | Some '-' -> advance st; loop (sub acc (term st))
    | _ -> acc
  in
  loop (term st)

and term st =
  let rec loop acc =
    match peek st with
    | Some '*' -> advance st; loop (mul acc (unary st))
    | Some '/' -> advance st; loop (div acc (unary st))
    | Some '%' -> advance st; loop (rem acc (unary st))
    | _ -> acc
  in
  loop (unary st)

and unary st =
  match peek st with
  | Some '-' -> advance st; neg (unary st)
  | _ -> primary st

and primary st =
  match peek st with
  | Some '0' .. '9' -> number st
  | Some '(' ->
      advance st;
      let v = expr st in
      (match peek st with Some ')' -> advance st | _ -> fail ());
      v
  | _ -> fail ()

let eval src =
  let st = { src; pos = 0 } in
  match expr st with
  | v -> if peek st = None then Ok v else Error ()
  | exception Error -> Error ()

let is_blank_line s = String.for_all is_blank s
