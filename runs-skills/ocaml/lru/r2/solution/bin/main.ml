(* Reads a capacity and a stream of cache commands from stdin and writes the
   results of GET, DEL and SIZE to stdout, one per line. *)

let strip_cr line =
  let n = String.length line in
  if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line

let read_line ic = Option.map strip_cr (In_channel.input_line ic)

let print_line oc s =
  Out_channel.output_string oc s;
  Out_channel.output_char oc '\n'

let execute cache oc line =
  match String.split_on_char ' ' line with
  | [ "SET"; key; value ] -> Lru.set cache key value
  | [ "GET"; key ] -> print_line oc (Option.value (Lru.get cache key) ~default:"NULL")
  | [ "DEL"; key ] -> print_line oc (if Lru.remove cache key then "1" else "0")
  | [ "SIZE" ] -> print_line oc (Int.to_string (Lru.size cache))
  | _ -> () (* Blank or malformed lines are ignored. *)

let fail msg =
  prerr_endline ("lru: " ^ msg);
  exit 2

let run ic oc =
  match Option.bind (read_line ic) (fun l -> int_of_string_opt (String.trim l)) with
  | None -> fail "expected a capacity on the first line"
  | Some capacity when capacity < 1 -> fail "capacity must be positive"
  | Some capacity ->
      let cache = Lru.create capacity in
      In_channel.fold_lines (fun () line -> execute cache oc (strip_cr line)) () ic;
      Out_channel.flush oc

let () = run stdin stdout
