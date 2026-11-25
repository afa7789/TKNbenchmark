(* wordfreq: print the 10 most frequent ASCII-letter words read from stdin. *)

let top_n = 10

(* Count every word in [ic]. A word is a maximal run of ASCII letters, folded
   to lowercase. Words may straddle read-chunk boundaries, so the current word
   is accumulated in a growable scratch buffer across chunks. *)
let count_words ic =
  let table = Word_table.create () in
  let word = ref (Bytes.create 256) in
  let word_len = ref 0 in
  let push c =
    if !word_len = Bytes.length !word then
      word := Bytes.extend !word 0 (Bytes.length !word);
    Bytes.unsafe_set !word !word_len c;
    incr word_len
  in
  let end_word () =
    if !word_len > 0 then begin
      Word_table.add table !word !word_len;
      word_len := 0
    end
  in
  let chunk = Bytes.create 65536 in
  let rec loop () =
    let len = In_channel.input ic chunk 0 (Bytes.length chunk) in
    if len > 0 then begin
      for i = 0 to len - 1 do
        match Bytes.unsafe_get chunk i with
        | 'a' .. 'z' as c -> push c
        | 'A' .. 'Z' as c -> push (Char.unsafe_chr (Char.code c + 32))
        | _ -> end_word ()
      done;
      loop ()
    end
  in
  loop ();
  end_word ();
  table

(* Output order: count descending, then word ascending (byte order). *)
let precedes (c1, w1) (c2, w2) = c1 > c2 || (c1 = c2 && String.compare w1 w2 < 0)

(* Insert [e] into the ordered list [top], keeping at most [top_n] entries. *)
let insert_bounded e top =
  let rec ins k = function
    | [] -> if k < top_n then [ e ] else []
    | x :: rest when precedes e x -> e :: List.take (top_n - k - 1) (x :: rest)
    | x :: rest -> x :: ins (k + 1) rest
  in
  List.take top_n (ins 0 top)

(* The [top_n] best words. Keys are only materialised for words whose count
   can still make the cut, so this stays cheap with millions of distinct
   words. *)
let top_words table =
  let top = ref [] and full = ref false and min_count = ref 0 in
  for id = 0 to Word_table.length table - 1 do
    let c = Word_table.count table id in
    if (not !full) || c >= !min_count then begin
      top := insert_bounded (c, Word_table.key table id) !top;
      full := List.length !top >= top_n;
      min_count := List.fold_left (fun m (c, _) -> min m c) max_int !top
    end
  done;
  !top

let () =
  set_binary_mode_in stdin true;
  let table = count_words stdin in
  let out = Buffer.create 256 in
  List.iter (fun (n, w) -> Printf.bprintf out "%d %s\n" n w) (top_words table);
  print_string (Buffer.contents out)
