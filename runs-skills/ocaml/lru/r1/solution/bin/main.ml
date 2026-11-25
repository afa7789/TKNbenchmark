(* Reads a capacity, then LRU cache commands, from standard input and writes
   one line of output per query command to standard output. *)

let run_command cache out line =
  match String.split_on_char ' ' line with
  | [ "SET"; key; value ] -> Lru.set cache key value
  | [ "GET"; key ] ->
      Buffer.add_string out (Option.value (Lru.get cache key) ~default:"NULL");
      Buffer.add_char out '\n'
  | [ "DEL"; key ] ->
      Buffer.add_string out (if Lru.remove cache key then "1\n" else "0\n")
  | [ "SIZE" ] ->
      Buffer.add_string out (string_of_int (Lru.size cache));
      Buffer.add_char out '\n'
  | _ -> () (* Blank or malformed lines are ignored. *)

let strip_cr line =
  let n = String.length line in
  if n > 0 && Char.equal line.[n - 1] '\r' then String.sub line 0 (n - 1) else line

let flush_threshold = 1 lsl 16

let () =
  match In_channel.input_line stdin with
  | None -> ()
  | Some first -> (
      match int_of_string_opt (String.trim first) with
      | None -> prerr_endline "lru: invalid capacity"
      | Some capacity when capacity < 1 -> prerr_endline "lru: invalid capacity"
      | Some capacity ->
          let cache = Lru.create capacity in
          let out = Buffer.create (2 * flush_threshold) in
          let rec loop () =
            match In_channel.input_line stdin with
            | None -> ()
            | Some line ->
                run_command cache out (strip_cr line);
                if Buffer.length out >= flush_threshold then begin
                  Buffer.output_buffer stdout out;
                  Buffer.clear out
                end;
                loop ()
          in
          loop ();
          Buffer.output_buffer stdout out;
          Out_channel.flush stdout)
