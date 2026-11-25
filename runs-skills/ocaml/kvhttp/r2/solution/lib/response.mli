(** HTTP responses. *)

type t = { status : int; headers : (string * string) list; body : string }

val make : ?headers:(string * string) list -> ?body:string -> int -> t
val reason : int -> string

val serialize : t -> string
(** Full HTTP/1.1 wire form, with [Content-Length] and [Connection: close]. *)
