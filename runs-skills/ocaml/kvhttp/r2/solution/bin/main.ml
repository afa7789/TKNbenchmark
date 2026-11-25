let usage () =
  prerr_endline "usage: app <port>";
  exit 2

let () =
  match Sys.argv with
  | [| _; port |] -> (
      match int_of_string_opt port with
      | Some p when p > 0 && p < 65536 -> (
          try Kvhttp.Server.run Unix.inet_addr_loopback p
          with Unix.Unix_error (e, fn, _) ->
            Printf.eprintf "app: %s: %s\n%!" fn (Unix.error_message e);
            exit 1)
      | Some _ | None -> usage ())
  | _ -> usage ()
