(* wordfreq: print the 10 most frequent ASCII words read from stdin. *)

let top_n = 10
let chunk_size = 65536

(* Count occurrences of every lowercase-folded word on [ic].
   Words may straddle chunk boundaries, so the current word is accumulated
   in a buffer that persists across reads. *)
let count_words ic =
  let counts : (string, int ref) Hashtbl.t = Hashtbl.create 4096 in
  let word = Buffer.create 64 in
  let flush_word () =
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
        | _ -> flush_word ()
      done;
      loop ()
    end
  in
  loop ();
  flush_word ();
  counts

(* Count descending, then word ascending (byte order). *)
let compare_entry (w1, c1) (w2, c2) =
  match Int.compare c2 c1 with 0 -> String.compare w1 w2 | c -> c

let top counts =
  Hashtbl.fold (fun w n acc -> (w, !n) :: acc) counts []
  |> List.sort compare_entry
  |> List.to_seq |> Seq.take top_n |> List.of_seq

let () =
  set_binary_mode_in stdin true;
  let entries = top (count_words stdin) in
  List.iter (fun (w, c) -> Printf.printf "%d %s\n" c w) entries
