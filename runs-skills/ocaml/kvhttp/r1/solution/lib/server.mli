(** Thread-per-connection HTTP server, one request per connection. *)

val run : ?backlog:int -> Unix.inet_addr -> int -> Store.t -> 'a
(** [run addr port store] binds, listens and serves forever. *)
