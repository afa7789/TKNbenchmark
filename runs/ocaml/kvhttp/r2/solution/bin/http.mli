(** Minimal HTTP/1.1 request reader and response writer, one request per
    connection. *)

type request = {
  meth : string;
  path : string;
  headers : (string * string) list;  (** Names lower-cased. *)
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

exception Error of int
(** Raised by {!read_request} with the status code to answer with when the
    request is malformed or exceeds limits. *)

val read_request : max_body:int -> Unix.file_descr -> request option
(** [None] if the peer closed before sending a request line. *)

val respond : ?headers:(string * string) list -> ?body:string -> int -> response
val write_response : Unix.file_descr -> response -> unit
