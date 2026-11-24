(* Reads an LRU capacity and a stream of commands from stdin, writing the
   result of each command that produces output to stdout. *)

let strip_cr line =
  let len = String.length line in
  if len > 0 && line.[len - 1] = '\r' then String.sub line 0 (len - 1) else line

let run_command cache out line =
  let emit s =
    Buffer.add_string out s;
    Buffer.add_char out '\n'
  in
  match String.split_on_char ' ' line with
  | [ "SET"; key; value ] -> Lru.set cache key value
  | [ "GET"; key ] -> emit (Option.value (Lru.get cache key) ~default:"NULL")
  | [ "DEL"; key ] -> emit (if Lru.remove cache key then "1" else "0")
  | [ "SIZE" ] -> emit (string_of_int (Lru.size cache))
  | _ -> ()

let () =
  match In_channel.input_line stdin with
  | None -> ()
  | Some first ->
      let capacity =
        match int_of_string_opt (String.trim first) with
        | Some c when c >= 1 -> c
        | _ ->
            prerr_endline "lru: invalid capacity";
            exit 2
      in
      let cache = Lru.create capacity in
      let out = Buffer.create (1 lsl 16) in
      let rec loop () =
        match In_channel.input_line stdin with
        | None -> ()
        | Some line ->
            run_command cache out (strip_cr line);
            if Buffer.length out >= 1 lsl 16 then begin
              Out_channel.output_string stdout (Buffer.contents out);
              Buffer.clear out
            end;
            loop ()
      in
      loop ();
      Out_channel.output_string stdout (Buffer.contents out);
      Out_channel.flush stdout
