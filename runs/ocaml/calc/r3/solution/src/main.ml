let () =
  let out = Buffer.create 65536 in
  let flush_if_large () =
    if Buffer.length out >= 65536 then begin
      print_string (Buffer.contents out);
      Buffer.clear out
    end
  in
  let rec loop () =
    match In_channel.input_line stdin with
    | None -> ()
    | Some line ->
        if not (Calc.is_blank_line line) then begin
          (match Calc.eval line with
           | Ok v -> Buffer.add_string out (Int64.to_string v)
           | Error () -> Buffer.add_string out "error");
          Buffer.add_char out '\n';
          flush_if_large ()
        end;
        loop ()
  in
  loop ();
  print_string (Buffer.contents out);
  exit 0
