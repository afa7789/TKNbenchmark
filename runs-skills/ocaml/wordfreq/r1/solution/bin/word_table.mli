(** A counting table for byte strings, tuned for very many distinct keys.

    Keys are stored back-to-back in a single byte arena and the hash table
    uses open addressing over plain [int] arrays, so the table holds no
    per-key heap blocks and puts essentially no load on the GC. *)

type t

val create : unit -> t

val add : t -> Bytes.t -> int -> unit
(** [add t buf len] increments the count of the key [Bytes.sub buf 0 len].
    [buf] is only read; it can be reused by the caller afterwards. *)

val length : t -> int
(** Number of distinct keys. *)

val count : t -> int -> int
(** [count t id] is the count of the key with id [id], for
    [0 <= id < length t]. Ids are assigned in insertion order. *)

val key : t -> int -> string
(** [key t id] is the key with id [id]. *)
