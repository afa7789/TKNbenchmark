type error =
  | Syntax
  | Division_by_zero
  | Overflow

exception Fail of error

let fail e = raise_notrace (Fail e)

(* Checked 64-bit arithmetic. *)

let add a b =
  let r = Int64.add a b in
  (* Overflow iff both operands share a sign that differs from the result. *)
  if Int64.logand (Int64.logxor a r) (Int64.logxor b r) < 0L then fail Overflow
  else r

let sub a b =
  let r = Int64.sub a b in
  (* Overflow iff operands differ in sign and the result's sign differs from [a]. *)
  if Int64.logand (Int64.logxor a b) (Int64.logxor a r) < 0L then fail Overflow
  else r

let neg a = if Int64.equal a Int64.min_int then fail Overflow else Int64.neg a

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

let is_space c = Char.equal c ' ' || Char.equal c '\t'

let is_blank s = String.for_all is_space s

let eval s =
  let len = String.length s in
  let pos = ref 0 in
  let rec skip () =
    if !pos < len && is_space s.[!pos] then (
      incr pos;
      skip ())
  in
  (* Next significant character, or ['\000'] at end of input. *)
  let peek () =
    skip ();
    if !pos < len then s.[!pos] else '\000'
  in
  let advance () = incr pos in
  let number () =
    let start = !pos in
    let rec digits acc =
      if !pos < len && Char.Ascii.is_digit s.[!pos] then begin
        let d = Int64.of_int (Char.code s.[!pos] - Char.code '0') in
        if Int64.compare acc (Int64.div (Int64.sub Int64.max_int d) 10L) > 0
        then fail Overflow;
        advance ();
        digits (Int64.add (Int64.mul acc 10L) d)
      end
      else acc
    in
    let n = digits 0L in
    if !pos = start then fail Syntax else n
  in
  let rec expr () =
    let rec loop acc =
      match peek () with
      | '+' -> advance (); loop (add acc (term ()))
      | '-' -> advance (); loop (sub acc (term ()))
      | _ -> acc
    in
    loop (term ())
  and term () =
    let rec loop acc =
      match peek () with
      | '*' -> advance (); loop (mul acc (unary ()))
      | '/' -> advance (); loop (div acc (unary ()))
      | '%' -> advance (); loop (rem acc (unary ()))
      | _ -> acc
    in
    loop (unary ())
  and unary () =
    match peek () with
    | '-' -> advance (); neg (unary ())
    | _ -> primary ()
  and primary () =
    match peek () with
    | '(' ->
        advance ();
        let v = expr () in
        if Char.equal (peek ()) ')' then (advance (); v) else fail Syntax
    | '0' .. '9' -> number ()
    | _ -> fail Syntax
  in
  match
    let v = expr () in
    skip ();
    if !pos < len then fail Syntax else v
  with
  | v -> Ok v
  | exception Fail e -> Error e
