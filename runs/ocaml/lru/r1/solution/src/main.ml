(* Reads a capacity and a stream of cache commands from stdin and writes
   the results of GET, DEL and SIZE to stdout, one per line. *)

let strip_cr line =
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line

let read_line () = Option.map strip_cr (In_channel.input_line stdin)

let rec read_capacity () =
  match read_line () with
  | None -> None
  | Some line -> (
      match String.trim line with
      | "" -> read_capacity ()
      | s -> int_of_string_opt s)

let execute cache out line =
  let emit s =
    Buffer.add_string out s;
    Buffer.add_char out '\n'
  in
  match String.split_on_char ' ' line with
  | [ "SET"; key; value ] -> Lru.set cache key value
  | [ "GET"; key ] -> emit (Option.value (Lru.get cache key) ~default:"NULL")
  | [ "DEL"; key ] -> emit (if Lru.remove cache key then "1" else "0")
  | [ "SIZE" ] -> emit (string_of_int (Lru.length cache))
  | _ -> () (* Blank or malformed lines are ignored. *)

let () =
  match read_capacity () with
  | None -> ()
  | Some capacity ->
      let cache = Lru.create (max 1 capacity) in
      let out = Buffer.create (1 lsl 16) in
      let rec loop () =
        match read_line () with
        | None -> ()
        | Some line ->
            execute cache out line;
            if Buffer.length out >= 1 lsl 16 then begin
              Out_channel.output_string stdout (Buffer.contents out);
              Buffer.clear out
            end;
            loop ()
      in
      loop ();
      Out_channel.output_string stdout (Buffer.contents out);
      Out_channel.flush stdout
