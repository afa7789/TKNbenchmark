(* wordfreq: print the 10 most frequent ASCII words read from stdin.

   A word is a maximal run of ASCII letters, folded to lowercase. The whole
   input is read into memory (inputs are bounded at ~50 MB) so words can be
   looked up as slices of it, allocating a string only for new words. *)

let top_n = 10

let[@inline] lower c =
  match c with 'A' .. 'Z' -> Char.unsafe_chr (Char.code c + 32) | c -> c

let[@inline] is_letter c = match c with 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false

(* Open-addressing hash table from lowercase words to counts. Keys are
   stored once, lowercased; lookups take a slice of the source text. *)
module Counter : sig
  type t

  val create : unit -> t

  val add_slice : t -> string -> pos:int -> len:int -> hash:int -> unit
  (** Count one occurrence of [lowercase (String.sub s pos len)], whose
      {!hash_step} hash is [hash]. *)

  val iter : (string -> int -> unit) -> t -> unit
end = struct
  type t = {
    mutable keys : string array;  (** [""] marks an empty slot. *)
    mutable hashes : int array;
    mutable counts : int array;
    mutable size : int;
  }

  let initial_capacity = 1 lsl 16

  let create () =
    {
      keys = Array.make initial_capacity "";
      hashes = Array.make initial_capacity 0;
      counts = Array.make initial_capacity 0;
      size = 0;
    }

  let mask t = Array.length t.keys - 1

  (* Does [key] equal the lowercased slice? *)
  let matches key s pos len =
    String.length key = len
    &&
    let rec go i = i = len || (String.unsafe_get key i = lower (String.unsafe_get s (pos + i)) && go (i + 1)) in
    go 0

  let grow t =
    let old_keys = t.keys and old_hashes = t.hashes and old_counts = t.counts in
    let cap = 2 * Array.length old_keys in
    t.keys <- Array.make cap "";
    t.hashes <- Array.make cap 0;
    t.counts <- Array.make cap 0;
    let m = cap - 1 in
    Array.iteri
      (fun i key ->
        if key <> "" then begin
          let h = old_hashes.(i) in
          let j = ref (h land m) in
          while t.keys.(!j) <> "" do
            j := (!j + 1) land m
          done;
          t.keys.(!j) <- key;
          t.hashes.(!j) <- h;
          t.counts.(!j) <- old_counts.(i)
        end)
      old_keys

  let rec add_slice t s ~pos ~len ~hash =
    let m = mask t in
    let rec probe i =
      let key = t.keys.(i) in
      if String.length key = 0 then begin
        if 2 * (t.size + 1) > Array.length t.keys then begin
          grow t;
          add_slice t s ~pos ~len ~hash
        end
        else begin
          t.keys.(i) <- String.init len (fun k -> lower (String.unsafe_get s (pos + k)));
          t.hashes.(i) <- hash;
          t.counts.(i) <- 1;
          t.size <- t.size + 1
        end
      end
      else if t.hashes.(i) = hash && matches key s pos len then t.counts.(i) <- t.counts.(i) + 1
      else probe ((i + 1) land m)
    in
    probe (hash land m)

  let iter f t = Array.iteri (fun i key -> if key <> "" then f key t.counts.(i)) t.keys
end

(* FNV-1a style hash over lowercase bytes, mixed at the end. *)
let[@inline] hash_step h c = (h lxor Char.code c) * 0x100000001b3

let[@inline] hash_finish h =
  let h = h lxor (h lsr 29) in
  (h * 0x3f58476d1ce4e5b9) lxor (h lsr 32)

let count_words s =
  let counter = Counter.create () in
  let n = String.length s in
  let rec skip i = if i < n && not (is_letter (String.unsafe_get s i)) then skip (i + 1) else i in
  let rec word start i h =
    if i < n && is_letter (String.unsafe_get s i) then word start (i + 1) (hash_step h (lower (String.unsafe_get s i)))
    else begin
      Counter.add_slice counter s ~pos:start ~len:(i - start) ~hash:(hash_finish h);
      next i
    end
  and next i =
    let i = skip i in
    if i < n then word i i 0x4bf29ce484222325
  in
  next 0;
  counter

(* [ranks_before (w1, n1) (w2, n2)]: count descending, then word ascending. *)
let ranks_before (w1, n1) (w2, n2) = n1 > n2 || (n1 = n2 && String.compare w1 w2 < 0)

(* The [top_n] best entries, best first, via insertion into a small sorted
   array rather than sorting every distinct word. *)
let top counter =
  let best = Array.make top_n ("", 0) in
  let size = ref 0 in
  Counter.iter
    (fun w n ->
      let entry = (w, n) in
      if !size < top_n || ranks_before entry best.(top_n - 1) then begin
        let i = ref (min !size (top_n - 1)) in
        while !i > 0 && ranks_before entry best.(!i - 1) do
          best.(!i) <- best.(!i - 1);
          decr i
        done;
        best.(!i) <- entry;
        if !size < top_n then incr size
      end)
    counter;
  Array.sub best 0 !size

let () =
  set_binary_mode_in stdin true;
  let input = In_channel.input_all stdin in
  let out = Buffer.create 256 in
  Array.iter (fun (w, n) -> Printf.bprintf out "%d %s\n" n w) (top (count_words input));
  print_string (Buffer.contents out)
