(* kvhttp: an in-memory key/value HTTP server, one thread per connection. *)

let recv_timeout = 30.0

(* Half-close and drain so the peer sees our response instead of a reset when
   it still has unread request bytes in flight. *)
let close_gracefully fd =
  (try Unix.shutdown fd Unix.SHUTDOWN_SEND with Unix.Unix_error _ -> ());
  (try
     Unix.setsockopt_float fd Unix.SO_RCVTIMEO 1.0;
     let buf = Bytes.create 65536 in
     let rec drain budget =
       if budget > 0 then
         match Unix.read fd buf 0 (Bytes.length buf) with
         | 0 -> ()
         | n -> drain (budget - n)
     in
     drain (16 lsl 20)
   with Unix.Unix_error _ -> ());
  try Unix.close fd with Unix.Unix_error _ -> ()

let serve_connection store fd =
  let reply resp = try Http.write_response fd resp with Unix.Unix_error _ -> () in
  (try
     Unix.setsockopt_float fd Unix.SO_RCVTIMEO recv_timeout;
     Unix.setsockopt_float fd Unix.SO_SNDTIMEO recv_timeout;
     match Http.read_request ~max_body:Router.max_value fd with
     | None -> ()
     | Some req -> reply (Router.handle store req)
   with
  | Http.Error status -> reply (Http.respond status)
  | Unix.Unix_error _ -> ()
  | exn ->
      Printf.eprintf "kvhttp: internal error: %s\n%!" (Printexc.to_string exn);
      reply (Http.respond 500));
  close_gracefully fd

let rec accept_loop store sock =
  (match Unix.accept ~cloexec:true sock with
   | fd, _ -> ignore (Thread.create (serve_connection store) fd : Thread.t)
   | exception Unix.Unix_error ((Unix.EINTR | Unix.ECONNABORTED), _, _) -> ()
   | exception Unix.Unix_error ((Unix.EMFILE | Unix.ENFILE), _, _) -> Thread.delay 0.05);
  accept_loop store sock

let usage () =
  prerr_endline "usage: app <port>";
  exit 2

let () =
  let port =
    match Sys.argv with
    | [| _; p |] -> (
        match int_of_string_opt p with
        | Some n when n > 0 && n < 65536 -> n
        | _ -> usage ())
    | _ -> usage ()
  in
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 1024;
  accept_loop (Store.create ()) sock
