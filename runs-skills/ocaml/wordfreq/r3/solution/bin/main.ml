(* wordfreq: print the 10 most frequent ASCII words read from stdin. *)

let top_n = 10

let is_letter c = match c with 'A' .. 'Z' | 'a' .. 'z' -> true | _ -> false

(* Count lowercase words in [text]. A word is a maximal run of ASCII letters. *)
let count_words (text : string) : (string, int ref) Hashtbl.t =
  let counts = Hashtbl.create 65536 in
  let len = String.length text in
  let add start stop =
    let word =
      String.init (stop - start) (fun i ->
          Char.lowercase_ascii (String.unsafe_get text (start + i)))
    in
    match Hashtbl.find_opt counts word with
    | Some n -> incr n
    | None -> Hashtbl.add counts word (ref 1)
  in
  let rec skip i =
    if i >= len then ()
    else if is_letter (String.unsafe_get text i) then scan i (i + 1)
    else skip (i + 1)
  and scan start i =
    if i < len && is_letter (String.unsafe_get text i) then scan start (i + 1)
    else begin
      add start i;
      skip i
    end
  in
  skip 0;
  counts

(* Order by count descending, then by word ascending (byte order). *)
let compare_entries (w1, c1) (w2, c2) =
  match Int.compare c2 c1 with 0 -> String.compare w1 w2 | c -> c

let top counts =
  Hashtbl.fold (fun w n acc -> (w, !n) :: acc) counts []
  |> List.sort compare_entries
  |> List.take top_n

let () =
  set_binary_mode_in stdin true;
  let text = In_channel.input_all stdin in
  let buf = Buffer.create 256 in
  List.iter
    (fun (w, c) -> Printf.bprintf buf "%d %s\n" c w)
    (top (count_words text));
  print_string (Buffer.contents buf)
