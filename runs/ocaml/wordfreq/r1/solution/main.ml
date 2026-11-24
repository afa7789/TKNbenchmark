(* wordfreq: print the 10 most frequent ASCII-letter words read from stdin. *)

let top_n = 10
let chunk_size = 65536

(** Count case-folded words from [ic]. A word is a maximal run of ASCII
    letters; every other byte is a separator. Words may span chunk
    boundaries, so the current word is accumulated in [word]. *)
let count_words ic =
  let counts : (string, int ref) Hashtbl.t = Hashtbl.create 65536 in
  let word = Buffer.create 64 in
  let flush () =
    if Buffer.length word > 0 then begin
      let w = Buffer.contents word in
      Buffer.clear word;
      match Hashtbl.find_opt counts w with
      | Some n -> incr n
      | None -> Hashtbl.add counts w (ref 1)
    end
  in
  let chunk = Bytes.create chunk_size in
  let rec loop () =
    let len = input ic chunk 0 chunk_size in
    if len > 0 then begin
      for i = 0 to len - 1 do
        match Bytes.unsafe_get chunk i with
        | 'a' .. 'z' as c -> Buffer.add_char word c
        | 'A' .. 'Z' as c -> Buffer.add_char word (Char.lowercase_ascii c)
        | _ -> flush ()
      done;
      loop ()
    end
  in
  loop ();
  flush ();
  counts

(** Ordering: count descending, then word ascending (byte order). *)
let compare_entry (w1, c1) (w2, c2) =
  match Int.compare c2 c1 with 0 -> String.compare w1 w2 | c -> c

(** Insert [x] into the sorted list [l], keeping at most [k] elements. *)
let insert_bounded k x l =
  let rec go i = function
    | [] -> if i < k then [ x ] else []
    | y :: rest when compare_entry x y < 0 ->
        if i < k then x :: take (k - i - 1) (y :: rest) else []
    | y :: rest -> if i < k then y :: go (i + 1) rest else []
  and take n = function
    | [] -> []
    | _ when n <= 0 -> []
    | y :: rest -> y :: take (n - 1) rest
  in
  go 0 l

let top k counts =
  Hashtbl.fold (fun w n acc -> insert_bounded k (w, !n) acc) counts []

let () =
  set_binary_mode_in stdin true;
  let counts = count_words stdin in
  let out = Buffer.create 256 in
  List.iter
    (fun (w, n) -> Printf.bprintf out "%d %s\n" n w)
    (top top_n counts);
  print_string (Buffer.contents out)
