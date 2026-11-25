(** A string-keyed LRU cache with O(1) expected-time operations. *)

type 'a t

val create : int -> 'a t
(** [create capacity] makes an empty cache holding at most [capacity] keys.
    @raise Invalid_argument if [capacity < 1]. *)

val set : 'a t -> string -> 'a -> unit
(** Insert or overwrite a binding, making it the most recently used.
    Evicts the least recently used binding when over capacity. *)

val get : 'a t -> string -> 'a option
(** Look up a binding; a hit makes it the most recently used. *)

val remove : 'a t -> string -> bool
(** Remove a binding; returns whether it was present. *)

val size : 'a t -> int
