type t = {
  mutable arena : Bytes.t;  (** all keys, concatenated *)
  mutable arena_len : int;
  mutable offsets : int array;  (** per id: start of key in [arena] *)
  mutable lengths : int array;  (** per id: key length *)
  mutable hashes : int array;  (** per id: full hash, reused on resize *)
  mutable counts : int array;  (** per id: occurrences *)
  mutable size : int;  (** number of ids in use *)
  mutable slots : int array;  (** [empty] or an id; length is a power of 2 *)
}

let empty = -1

let create () =
  let cap = 1024 in
  {
    arena = Bytes.create (16 * cap);
    arena_len = 0;
    offsets = Array.make cap 0;
    lengths = Array.make cap 0;
    hashes = Array.make cap 0;
    counts = Array.make cap 0;
    size = 0;
    slots = Array.make (2 * cap) empty;
  }

let length t = t.size
let count t id = t.counts.(id)
let key t id = Bytes.sub_string t.arena t.offsets.(id) t.lengths.(id)

(* FNV-1a over the bytes, followed by a final avalanche so that the low bits
   used for slot selection depend on every input byte. *)
let hash buf len =
  let h = ref 0x0bf29ce484222325 in
  for i = 0 to len - 1 do
    h := (!h lxor Char.code (Bytes.unsafe_get buf i)) * 0x100000001b3
  done;
  let h = !h in
  let h = (h lxor (h lsr 32)) * 0x16e8feb86659fd93 in
  h lxor (h lsr 29)

let key_equal t id buf len =
  t.lengths.(id) = len
  &&
  let off = t.offsets.(id) in
  let rec go i =
    i >= len
    || Char.equal (Bytes.unsafe_get t.arena (off + i)) (Bytes.unsafe_get buf i)
       && go (i + 1)
  in
  go 0

let grow_array a n fill =
  let b = Array.make n fill in
  Array.blit a 0 b 0 (Array.length a);
  b

(* Called when the id arrays are full; keeps the load factor at most 1/2. *)
let grow t =
  let cap = 2 * Array.length t.offsets in
  t.offsets <- grow_array t.offsets cap 0;
  t.lengths <- grow_array t.lengths cap 0;
  t.hashes <- grow_array t.hashes cap 0;
  t.counts <- grow_array t.counts cap 0;
  let slots = Array.make (2 * cap) empty in
  let mask = Array.length slots - 1 in
  for id = 0 to t.size - 1 do
    let i = ref (t.hashes.(id) land mask) in
    while slots.(!i) <> empty do
      i := (!i + 1) land mask
    done;
    slots.(!i) <- id
  done;
  t.slots <- slots

let append_key t buf len =
  let needed = t.arena_len + len in
  if needed > Bytes.length t.arena then begin
    let arena = Bytes.create (max needed (2 * Bytes.length t.arena)) in
    Bytes.blit t.arena 0 arena 0 t.arena_len;
    t.arena <- arena
  end;
  Bytes.blit buf 0 t.arena t.arena_len len;
  let off = t.arena_len in
  t.arena_len <- needed;
  off

let insert t slot h buf len =
  let id = t.size in
  t.offsets.(id) <- append_key t buf len;
  t.lengths.(id) <- len;
  t.hashes.(id) <- h;
  t.counts.(id) <- 1;
  t.slots.(slot) <- id;
  t.size <- id + 1;
  if t.size = Array.length t.offsets then grow t

let add t buf len =
  let h = hash buf len in
  let mask = Array.length t.slots - 1 in
  let rec probe i =
    let id = t.slots.(i) in
    if id = empty then insert t i h buf len
    else if t.hashes.(id) = h && key_equal t id buf len then
      t.counts.(id) <- t.counts.(id) + 1
    else probe ((i + 1) land mask)
  in
  probe (h land mask)
