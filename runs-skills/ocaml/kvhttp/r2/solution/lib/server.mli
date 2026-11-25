(** Thread-per-connection HTTP server over the key-value store. *)

val handle_connection : Store.t -> Unix.file_descr -> unit
(** Serves one request on [fd] and closes it. Never raises on I/O errors. *)

val run : ?backlog:int -> Unix.inet_addr -> int -> unit
(** [run addr port] listens on [addr:port] and serves forever. *)
