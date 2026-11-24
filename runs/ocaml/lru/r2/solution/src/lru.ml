(* Hash table indexing the nodes of a circular doubly linked list. The list is
   anchored by a sentinel; [sentinel.next] is the most recently used node and
   [sentinel.prev] the least recently used one. *)

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
  { capacity; table = Hashtbl.create (min capacity 65_536); sentinel }

let unlink node =
  node.prev.next <- node.next;
  node.next.prev <- node.prev

let push_front t node =
  let first = t.sentinel.next in
  node.prev <- t.sentinel;
  node.next <- first;
  first.prev <- node;
  t.sentinel.next <- node

let touch t node =
  unlink node;
  push_front t node

let evict_lru t =
  let lru = t.sentinel.prev in
  if lru != t.sentinel then begin
    unlink lru;
    Hashtbl.remove t.table lru.key
  end

let set t key value =
  match Hashtbl.find_opt t.table key with
  | Some node ->
      node.value <- value;
      touch t node
  | None ->
      let rec node = { key; value; prev = node; next = node } in
      Hashtbl.replace t.table key node;
      push_front t node;
      if Hashtbl.length t.table > t.capacity then evict_lru t

let get t key =
  match Hashtbl.find_opt t.table key with
  | Some node ->
      touch t node;
      Some node.value
  | None -> None

let remove t key =
  match Hashtbl.find_opt t.table key with
  | Some node ->
      unlink node;
      Hashtbl.remove t.table key;
      true
  | None -> false

let size t = Hashtbl.length t.table
