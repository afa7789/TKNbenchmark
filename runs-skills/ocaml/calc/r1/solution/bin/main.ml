let () =
  let out = Buffer.create 65536 in
  In_channel.fold_lines
    (fun () line ->
      if not (Calc.is_blank line) then begin
        (match Calc.eval line with
         | Ok v -> Buffer.add_string out (Int64.to_string v)
         | Error (Syntax_error | Division_by_zero | Overflow) ->
             Buffer.add_string out "error");
        Buffer.add_char out '\n';
        if Buffer.length out >= 65536 then begin
          Buffer.output_buffer stdout out;
          Buffer.clear out
        end
      end)
    () stdin;
  Buffer.output_buffer stdout out;
  Out_channel.flush stdout
