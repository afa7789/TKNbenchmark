(* kvhttp: an in-memory key/value HTTP server. Usage: ./app <port> *)

let client_timeout = 30.0

let serve_client store fd =
  Fun.protect
    ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
    (fun () ->
      try
        Unix.setsockopt_float fd Unix.SO_RCVTIMEO client_timeout;
        Unix.setsockopt_float fd Unix.SO_SNDTIMEO client_timeout;
        let response =
          match Http.read_request fd with
          | req -> Some (Router.handle store req)
          | exception Http.Bad_request (status, _) ->
              Some { Http.status; content_type = None; body = "" }
          | exception End_of_file -> None
        in
        Option.iter (Http.write_response fd) response;
        (try Unix.shutdown fd Unix.SHUTDOWN_SEND with Unix.Unix_error _ -> ())
      with
      | Unix.Unix_error _ | End_of_file -> ()
      | exn ->
          Printf.eprintf "kvhttp: unexpected error: %s\n%!"
            (Printexc.to_string exn))

let rec accept_loop store sock =
  (match Unix.accept ~cloexec:true sock with
  | fd, _ -> ignore (Thread.create (serve_client store) fd : Thread.t)
  | exception Unix.Unix_error ((Unix.EINTR | Unix.ECONNABORTED), _, _) -> ()
  | exception Unix.Unix_error ((Unix.EMFILE | Unix.ENFILE), _, _) ->
      (* Out of descriptors: back off briefly rather than spin. *)
      Thread.delay 0.05);
  accept_loop store sock

let listen port =
  let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 1024;
  sock

let () =
  let port =
    match Sys.argv with
    | [| _; p |] -> (
        match int_of_string_opt p with
        | Some n when n > 0 && n < 65536 -> n
        | _ ->
            prerr_endline "kvhttp: invalid port";
            exit 2)
    | _ ->
        prerr_endline "usage: app <port>";
        exit 2
  in
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let sock =
    try listen port
    with Unix.Unix_error (e, _, _) ->
      Printf.eprintf "kvhttp: cannot listen on port %d: %s\n" port
        (Unix.error_message e);
      exit 1
  in
  accept_loop (Store.create ()) sock
