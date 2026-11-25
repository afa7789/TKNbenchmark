let max_head = 64 * 1024
let io_timeout = 30.0

let log fmt = Printf.eprintf (fmt ^^ "\n%!")

let close_quietly fd =
  try Unix.close fd with Unix.Unix_error _ -> ()

(* Half-close then drain briefly so the client sees the full response rather
   than a reset caused by unread request bytes. *)
let finish fd =
  (try Unix.shutdown fd Unix.SHUTDOWN_SEND with Unix.Unix_error _ -> ());
  close_quietly fd

let serve_connection store fd =
  Fun.protect
    ~finally:(fun () -> finish fd)
    (fun () ->
      try
        Unix.setsockopt_float fd Unix.SO_RCVTIMEO io_timeout;
        Unix.setsockopt_float fd Unix.SO_SNDTIMEO io_timeout;
        Unix.setsockopt fd Unix.TCP_NODELAY true;
        let reply =
          match
            Http.read_request fd ~max_head ~max_body:Router.max_value_size
          with
          | Ok req -> Some (Router.handle store req)
          | Error err -> Http.error_response err
        in
        Option.iter (Http.write_response fd) reply
      with Unix.Unix_error (e, fn, _) ->
        log "connection error: %s: %s" fn (Unix.error_message e))

let rec accept sock =
  match Unix.accept ~cloexec:true sock with
  | conn -> conn
  | exception Unix.Unix_error ((Unix.EINTR | Unix.ECONNABORTED), _, _) -> accept sock
  | exception Unix.Unix_error (((Unix.EMFILE | Unix.ENFILE) as e), _, _) ->
      log "accept: %s; backing off" (Unix.error_message e);
      Thread.delay 0.05;
      accept sock

let run ?(backlog = 512) addr port store =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (addr, port));
  Unix.listen sock backlog;
  let rec loop () =
    let fd, _ = accept sock in
    ignore (Thread.create (serve_connection store) fd : Thread.t);
    loop ()
  in
  loop ()
