let usage () =
  prerr_endline "usage: app <port>";
  exit 2

let () =
  match Sys.argv with
  | [| _; port |] -> (
      match int_of_string_opt port with
      | Some port when port > 0 && port < 65536 ->
          Kvhttp.Server.run Unix.inet_addr_loopback port (Kvhttp.Store.create ())
      | Some _ | None -> usage ())
  | _ -> usage ()
