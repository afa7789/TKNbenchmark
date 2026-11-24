(* Reads a capacity and a stream of cache commands from stdin, writing one
   line of output per GET, DEL and SIZE command. *)

let strip_cr line =
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line

let run_command cache out line =
  match String.split_on_char ' ' line with
  | [ "SET"; key; value ] -> Lru.set cache key value
  | [ "GET"; key ] ->
      Buffer.add_string out
        (match Lru.get cache key with Some v -> v | None -> "NULL");
      Buffer.add_char out '\n'
  | [ "DEL"; key ] ->
      Buffer.add_string out (if Lru.remove cache key then "1\n" else "0\n")
  | [ "SIZE" ] ->
      Buffer.add_string out (string_of_int (Lru.size cache));
      Buffer.add_char out '\n'
  | _ -> () (* Blank or malformed lines are ignored. *)

let flush_threshold = 1 lsl 16

let () =
  match In_channel.input_line stdin with
  | None -> ()
  | Some first -> (
      match int_of_string_opt (String.trim first) with
      | None ->
          prerr_endline "lru: invalid capacity";
          exit 1
      | Some capacity ->
          let cache = Lru.create (max capacity 1) in
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
          flush stdout)
