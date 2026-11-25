(* kvhttp: in-memory key-value HTTP/1.1 server, one thread per connection. *)

open Kvhttp

let io_timeout = 30.0

let serve_connection store fd =
  let ic = Unix.in_channel_of_descr fd and oc = Unix.out_channel_of_descr fd in
  Fun.protect
    ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
    (fun () ->
      try
        Unix.setsockopt_float fd Unix.SO_RCVTIMEO io_timeout;
        Unix.setsockopt_float fd Unix.SO_SNDTIMEO io_timeout;
        let response =
          match Http.read_request ~max_body:Router.max_value ic with
          | Ok req -> Some (Router.handle store req)
          | Error e -> Http.error_response e
        in
        Option.iter (Http.write_response oc) response
      with Sys_error _ | Unix.Unix_error _ | End_of_file -> ())

let rec accept_loop store sock =
  match Unix.accept ~cloexec:true sock with
  | fd, _ ->
      ignore (Thread.create (serve_connection store) fd : Thread.t);
      accept_loop store sock
  | exception Unix.Unix_error ((Unix.EINTR | Unix.ECONNABORTED | Unix.EMFILE | Unix.ENFILE), _, _) ->
      accept_loop store sock

let listen port =
  let sock = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 1024;
  sock

let () =
  match Sys.argv with
  | [| _; port |] -> (
      match int_of_string_opt port with
      | Some port when port > 0 && port < 65536 ->
          Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
          accept_loop (Store.create ()) (listen port)
      | Some _ | None ->
          Printf.eprintf "invalid port: %s\n%!" port;
          exit 2)
  | _ ->
      Printf.eprintf "usage: %s <port>\n%!" Sys.argv.(0);
      exit 2
