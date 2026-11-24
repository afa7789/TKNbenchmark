(** Thread-per-connection HTTP server for the key-value API. *)

val run : port:int -> unit
(** Listen on 127.0.0.1:[port] and serve forever. *)
