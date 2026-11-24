(* Hash table from key to node, plus a circular doubly linked list with a
   sentinel. The node after the sentinel is the most recently used; the node
   before it is the least recently used. *)

type node = {
  key : string;
  mutable value : string;
  mutable prev : node;
  mutable next : node;
}

type t = {
  capacity : int;
  table : (string, node) Hashtbl.t;
  sentinel : node;
}

let create capacity =
  if capacity < 1 then invalid_arg "Lru.create: capacity must be positive";
  let rec sentinel = { key = ""; value = ""; prev = sentinel; next = sentinel } in
  { capacity; table = Hashtbl.create (min capacity 65536); sentinel }

let unlink n =
  n.prev.next <- n.next;
  n.next.prev <- n.prev

let push_front t n =
  let s = t.sentinel in
  n.prev <- s;
  n.next <- s.next;
  s.next.prev <- n;
  s.next <- n

let touch t n =
  unlink n;
  push_front t n

let size t = Hashtbl.length t.table

let evict_lru t =
  let lru = t.sentinel.prev in
  if lru != t.sentinel then begin
    unlink lru;
    Hashtbl.remove t.table lru.key
  end

let set t key value =
  match Hashtbl.find_opt t.table key with
  | Some n ->
      n.value <- value;
      touch t n
  | None ->
      let s = t.sentinel in
      let n = { key; value; prev = s; next = s } in
      push_front t n;
      Hashtbl.replace t.table key n;
      if size t > t.capacity then evict_lru t

let get t key =
  match Hashtbl.find_opt t.table key with
  | Some n ->
      touch t n;
      Some n.value
  | None -> None

let remove t key =
  match Hashtbl.find_opt t.table key with
  | Some n ->
      unlink n;
      Hashtbl.remove t.table key;
      true
  | None -> false
