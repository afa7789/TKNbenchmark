let io_timeout = 30.

let rec write_all fd s off len =
  if len > 0 then begin
    let n = Unix.write_substring fd s off len in
    write_all fd s (off + n) (len - n)
  end

let respond_error = function
  | `Bad_request -> Some (Response.make 400)
  | `Header_too_large -> Some (Response.make 431)
  | `Body_too_large -> Some (Response.make 413)
  | `Eof -> None

let log_exn e =
  Printf.eprintf "kvhttp: connection error: %s\n%!" (Printexc.to_string e)

let serve store fd =
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO io_timeout;
  Unix.setsockopt_float fd Unix.SO_SNDTIMEO io_timeout;
  let ic = Unix.in_channel_of_descr fd in
  let response =
    match Request.read ~max_body:Router.max_value_size ic with
    | Ok { meth; path; body; headers = _ } ->
        Some (Router.handle store ~meth ~path ~body)
    | Error e -> respond_error e
  in
  Option.iter
    (fun r ->
      let wire = Response.serialize r in
      write_all fd wire 0 (String.length wire))
    response

let handle_connection store fd =
  Fun.protect
    ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
    (fun () ->
      try serve store fd with
      | Unix.Unix_error ((EPIPE | ECONNRESET | EAGAIN | EWOULDBLOCK), _, _)
      | Sys_error _ ->
          (* Client went away or timed out; nothing useful to report. *)
          ()
      | Unix.Unix_error _ as e -> log_exn e)

let rec accept_loop store sock =
  match Unix.accept ~cloexec:true sock with
  | fd, _ ->
      ignore (Thread.create (handle_connection store) fd : Thread.t);
      accept_loop store sock
  | exception Unix.Unix_error ((EINTR | ECONNABORTED | EAGAIN), _, _) ->
      accept_loop store sock
  | exception (Unix.Unix_error ((EMFILE | ENFILE), _, _) as e) ->
      log_exn e;
      Thread.delay 0.05;
      accept_loop store sock

let run ?(backlog = 1024) addr port =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (addr, port));
  Unix.listen sock backlog;
  accept_loop (Store.create ()) sock
