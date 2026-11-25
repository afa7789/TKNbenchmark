(** Minimal HTTP/1.1 message handling: one request per connection. *)

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

type read_error =
  | Closed  (** Peer closed before sending a complete request head. *)
  | Bad_request of string
  | Header_too_large
  | Payload_too_large
  | Not_implemented of string

val response : ?headers:(string * string) list -> ?body:string -> int -> response

val error_response : read_error -> response option
(** The response to send for a read error, if any. *)

val parse_head : string -> (string * string * (string * string) list, read_error) result
(** [parse_head head] parses the request line and header block (without the
    terminating blank line) into method, target and lower-cased headers. *)

val read_request :
  Unix.file_descr -> max_head:int -> max_body:int -> (request, read_error) result

val write_response : Unix.file_descr -> response -> unit
