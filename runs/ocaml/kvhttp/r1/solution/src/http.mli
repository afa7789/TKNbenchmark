(** Minimal HTTP/1.x message parsing and serialisation over Unix sockets. *)

type request = {
  meth : string;
  target : string;
  version : string;  (** e.g. ["HTTP/1.1"] *)
  headers : (string * string) list;  (** names lower-cased, in arrival order *)
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

val response : ?headers:(string * string) list -> ?body:string -> int -> response

val header : request -> string -> string option
(** [header req name] is the first value of header [name] (case-insensitive). *)

val wants_keep_alive : request -> bool

(** Buffered reader over a connected socket. *)
module Reader : sig
  type t

  val create : Unix.file_descr -> t
end

type read_error =
  [ `Eof  (** connection closed (or timed out) before a full request arrived *)
  | `Status of int  (** malformed or unacceptable request; reply with this status *) ]

val read_request :
  ?on_continue:(unit -> unit) -> max_body:int -> Reader.t -> (request, read_error) result
(** Read one request. Bodies larger than [max_body] yield [`Status 413] (after
    draining the body when that is cheap, so the client can read the reply).
    [on_continue] is called before reading the body of a request that sent
    [Expect: 100-continue]. *)

val write_response : Unix.file_descr -> close:bool -> response -> unit
(** Serialise [response], adding [Content-Length] (except for 204/304) and
    [Connection: close] when [close] holds. *)

val write_continue : Unix.file_descr -> unit
