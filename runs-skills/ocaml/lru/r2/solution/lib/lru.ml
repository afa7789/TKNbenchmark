(* Entries live in parallel arrays indexed by slot; the recency order is an
   intrusive doubly linked list over slots, threaded through [prev]/[next].
   Slot [sentinel] (= capacity) is the list head: [next.(sentinel)] is the
   most recently used slot and [prev.(sentinel)] the least recently used.
   Free slots are chained through [next], starting at [free]. *)

type t = {
  capacity : int;
  index : (string, int) Hashtbl.t;
  keys : string array;
  values : string array;
  prev : int array;
  next : int array;
  mutable free : int;
  mutable size : int;
}

let nil = -1

let create capacity =
  if capacity < 1 then invalid_arg "Lru.create: capacity must be positive";
  let sentinel = capacity in
  let next = Array.init (capacity + 1) (fun i -> if i + 1 < capacity then i + 1 else nil) in
  let prev = Array.make (capacity + 1) nil in
  next.(sentinel) <- sentinel;
  prev.(sentinel) <- sentinel;
  {
    capacity;
    index = Hashtbl.create (min capacity 65536);
    keys = Array.make capacity "";
    values = Array.make capacity "";
    prev;
    next;
    free = 0;
    size = 0;
  }

let sentinel t = t.capacity

let unlink t i =
  let p = t.prev.(i) and n = t.next.(i) in
  t.next.(p) <- n;
  t.prev.(n) <- p

let push_front t i =
  let s = sentinel t in
  let first = t.next.(s) in
  t.prev.(i) <- s;
  t.next.(i) <- first;
  t.prev.(first) <- i;
  t.next.(s) <- i

let touch t i =
  if t.next.(sentinel t) <> i then begin
    unlink t i;
    push_front t i
  end

let release t i =
  t.keys.(i) <- "";
  t.values.(i) <- "";
  t.next.(i) <- t.free;
  t.free <- i;
  t.size <- t.size - 1

(* A slot for a new entry, evicting the least recently used one if full. *)
let acquire t =
  if t.free = nil then begin
    let lru = t.prev.(sentinel t) in
    unlink t lru;
    Hashtbl.remove t.index t.keys.(lru);
    release t lru
  end;
  let i = t.free in
  t.free <- t.next.(i);
  t.size <- t.size + 1;
  i

let set t key value =
  match Hashtbl.find_opt t.index key with
  | Some i ->
      t.values.(i) <- value;
      touch t i
  | None ->
      let i = acquire t in
      t.keys.(i) <- key;
      t.values.(i) <- value;
      push_front t i;
      Hashtbl.replace t.index key i

let get t key =
  match Hashtbl.find_opt t.index key with
  | Some i ->
      touch t i;
      Some t.values.(i)
  | None -> None

let remove t key =
  match Hashtbl.find_and_remove t.index key with
  | Some i ->
      unlink t i;
      release t i;
      true
  | None -> false

let size t = t.size
