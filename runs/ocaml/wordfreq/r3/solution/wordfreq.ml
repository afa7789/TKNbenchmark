(* wordfreq: print the 10 most frequent ASCII words read from stdin. *)

let top_n = 10
let chunk_size = 1 lsl 16

let is_upper c = c >= 'A' && c <= 'Z'
let is_lower c = c >= 'a' && c <= 'z'

(* Count every word on [ic]. Words are lowercased; a word that straddles
   a chunk boundary is accumulated in [carry]. *)
let count_words ic =
  let counts : (string, int ref) Hashtbl.t = Hashtbl.create 4096 in
  let record word =
    match Hashtbl.find_opt counts word with
    | Some n -> incr n
    | None -> Hashtbl.add counts word (ref 1)
  in
  let buf = Bytes.create chunk_size in
  let carry = Buffer.create 64 in
  let rec loop () =
    let len = input ic buf 0 chunk_size in
    if len > 0 then begin
      (* [start] is the index where the current in-chunk word began, or -1. *)
      let start = ref (if Buffer.length carry > 0 then 0 else -1) in
      for i = 0 to len - 1 do
        let c = Bytes.unsafe_get buf i in
        if is_lower c then (if !start < 0 then start := i)
        else if is_upper c then begin
          Bytes.unsafe_set buf i (Char.unsafe_chr (Char.code c + 32));
          if !start < 0 then start := i
        end
        else if !start >= 0 then begin
          if Buffer.length carry > 0 then begin
            Buffer.add_subbytes carry buf !start (i - !start);
            record (Buffer.contents carry);
            Buffer.clear carry
          end
          else record (Bytes.sub_string buf !start (i - !start));
          start := -1
        end
      done;
      if !start >= 0 then Buffer.add_subbytes carry buf !start (len - !start);
      loop ()
    end
  in
  loop ();
  if Buffer.length carry > 0 then record (Buffer.contents carry);
  counts

let compare_entry (w1, c1) (w2, c2) =
  match Int.compare c2 c1 with 0 -> String.compare w1 w2 | n -> n

let () =
  set_binary_mode_in stdin true;
  let counts = count_words stdin in
  let entries =
    Hashtbl.fold (fun w n acc -> (w, !n) :: acc) counts [] |> Array.of_list
  in
  Array.sort compare_entry entries;
  let out = Buffer.create 256 in
  Array.iteri
    (fun i (w, n) ->
      if i < top_n then Printf.bprintf out "%d %s\n" n w)
    entries;
  print_string (Buffer.contents out)
