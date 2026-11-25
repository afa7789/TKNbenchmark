type error =
  | Syntax_error
  | Division_by_zero
  | Overflow

exception Error of error

let fail e = raise_notrace (Error e)

(* Checked 64-bit arithmetic. *)

let neg a = if Int64.equal a Int64.min_int then fail Overflow else Int64.neg a

let add a b =
  let r = Int64.add a b in
  (* Overflow iff both operands share a sign that the result lacks. *)
  if Int64.compare (Int64.logand (Int64.logxor a r) (Int64.logxor b r)) 0L < 0
  then fail Overflow
  else r

let sub a b =
  let r = Int64.sub a b in
  (* Overflow iff operands differ in sign and the result's sign differs from [a]. *)
  if Int64.compare (Int64.logand (Int64.logxor a b) (Int64.logxor a r)) 0L < 0
  then fail Overflow
  else r

let mul a b =
  if Int64.equal a 0L || Int64.equal b 0L then 0L
  else if
    (Int64.equal a (-1L) && Int64.equal b Int64.min_int)
    || (Int64.equal b (-1L) && Int64.equal a Int64.min_int)
  then fail Overflow
  else
    let r = Int64.mul a b in
    if Int64.equal (Int64.div r b) a then r else fail Overflow

let div a b =
  if Int64.equal b 0L then fail Division_by_zero
  else if Int64.equal b (-1L) then neg a
  else Int64.div a b

let rem a b =
  if Int64.equal b 0L then fail Division_by_zero
  else if Int64.equal b (-1L) then 0L
  else Int64.rem a b

(* Recursive-descent parser that evaluates as it goes. *)

type state = { src : string; mutable pos : int }

let is_space = function ' ' | '\t' -> true | _ -> false
let is_digit = function '0' .. '9' -> true | _ -> false

let rec skip_spaces st =
  if st.pos < String.length st.src && is_space st.src.[st.pos] then begin
    st.pos <- st.pos + 1;
    skip_spaces st
  end

(** Next non-blank character, without consuming it. *)
let peek st =
  skip_spaces st;
  if st.pos < String.length st.src then Some st.src.[st.pos] else None

let advance st = st.pos <- st.pos + 1

let number st =
  let len = String.length st.src in
  let rec go acc =
    if st.pos < len && is_digit st.src.[st.pos] then begin
      let d = Int64.of_int (Char.code st.src.[st.pos] - Char.code '0') in
      (* acc * 10 + d <= max_int  <=>  acc <= (max_int - d) / 10 *)
      if Int64.compare acc (Int64.div (Int64.sub Int64.max_int d) 10L) > 0 then
        fail Overflow;
      advance st;
      go (Int64.add (Int64.mul acc 10L) d)
    end
    else acc
  in
  go 0L

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
  | Some '(' ->
      advance st;
      let v = expr st in
      (match peek st with
       | Some ')' -> advance st; v
       | _ -> fail Syntax_error)
  | Some c when is_digit c -> number st
  | _ -> fail Syntax_error

let eval src =
  let st = { src; pos = 0 } in
  match
    let v = expr st in
    match peek st with None -> v | Some _ -> fail Syntax_error
  with
  | v -> Ok v
  | exception Error e -> Error e

let is_blank s = String.for_all is_space s
