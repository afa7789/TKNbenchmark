(* Reads a capacity and a stream of cache commands from stdin and prints
   the results of GET, DEL and SIZE to stdout (which is buffered). *)

let strip_cr line =
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line

let print_line s =
  Out_channel.output_string stdout s;
  Out_channel.output_char stdout '\n'

let run_command cache line =
  match String.split_on_char ' ' (strip_cr line) with
  | [ "SET"; key; value ] -> Lru.set cache key value
  | [ "GET"; key ] -> print_line (Option.value (Lru.get cache key) ~default:"NULL")
  | [ "DEL"; key ] -> print_line (if Lru.remove cache key then "1" else "0")
  | [ "SIZE" ] -> print_line (Int.to_string (Lru.size cache))
  | _ -> () (* blank or malformed line: ignore *)

let () =
  let capacity =
    Option.bind (In_channel.input_line stdin) (fun line ->
        int_of_string_opt (String.trim line))
  in
  Option.iter
    (fun capacity ->
      let cache = Lru.create (max 1 capacity) in
      In_channel.fold_lines (fun () line -> run_command cache line) () stdin)
    capacity;
  Out_channel.flush stdout
