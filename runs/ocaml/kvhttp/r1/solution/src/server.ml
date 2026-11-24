let idle_timeout = 30.0
let backlog = 1024

let close_quietly fd = try Unix.close fd with Unix.Unix_error _ -> ()

let serve_connection store fd =
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO idle_timeout;
  Unix.setsockopt_float fd Unix.SO_SNDTIMEO idle_timeout;
  let reader = Http.Reader.create fd in
  let on_continue () = Http.write_continue fd in
  let rec loop () =
    match Http.read_request ~on_continue ~max_body:Store.max_value_size reader with
    | Error `Eof -> ()
    | Error (`Status status) -> Http.write_response fd ~close:true (Http.response status)
    | Ok req ->
        let resp =
          try Router.handle store req
          with e ->
            Printf.eprintf "kvhttp: handler error: %s\n%!" (Printexc.to_string e);
            Http.response 500
        in
        let keep_alive = Http.wants_keep_alive req in
        Http.write_response fd ~close:(not keep_alive) resp;
        if keep_alive then loop ()
  in
  (try loop () with
  | Unix.Unix_error ((EPIPE | ECONNRESET | EAGAIN | EWOULDBLOCK | ETIMEDOUT), _, _) -> ()
  | e -> Printf.eprintf "kvhttp: connection error: %s\n%!" (Printexc.to_string e));
  (try Unix.shutdown fd Unix.SHUTDOWN_SEND with Unix.Unix_error _ -> ());
  close_quietly fd

let listen port =
  let fd = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt fd Unix.SO_REUSEADDR true;
  Unix.bind fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen fd backlog;
  fd

let rec accept_loop store sock =
  (match Unix.accept ~cloexec:true sock with
  | client, _ ->
      Unix.setsockopt client Unix.TCP_NODELAY true;
      ignore (Thread.create (serve_connection store) client : Thread.t)
  | exception Unix.Unix_error ((EINTR | ECONNABORTED | EAGAIN), _, _) -> ()
  | exception Unix.Unix_error (((EMFILE | ENFILE | ENOBUFS | ENOMEM) as err), _, _) ->
      Printf.eprintf "kvhttp: accept: %s\n%!" (Unix.error_message err);
      Thread.delay 0.05);
  accept_loop store sock

let run ~port =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let store = Store.create () in
  let sock = listen port in
  accept_loop store sock
