let () =
  In_channel.fold_lines
    (fun () line ->
      if not (Calc.is_blank line) then
        let result =
          match Calc.eval line with
          | Ok v -> Int64.to_string v
          | Error (Syntax | Division_by_zero | Overflow) -> "error"
        in
        Out_channel.output_string stdout result;
        Out_channel.output_char stdout '\n')
    () stdin;
  Out_channel.flush stdout
