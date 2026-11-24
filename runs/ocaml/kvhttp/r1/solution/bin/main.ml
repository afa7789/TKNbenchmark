let usage () =
  prerr_endline "usage: app <port>";
  exit 2

let () =
  match Sys.argv with
  | [| _; port |] -> (
      match int_of_string_opt port with
      | Some port when port > 0 && port < 65536 -> (
          try Kvhttp.Server.run ~port
          with Unix.Unix_error (err, fn, _) ->
            Printf.eprintf "app: %s: %s\n" fn (Unix.error_message err);
            exit 1)
      | _ -> usage ())
  | _ -> usage ()
