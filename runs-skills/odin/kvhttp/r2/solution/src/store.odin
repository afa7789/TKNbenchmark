package main

import "core:slice"
import "core:strings"
import "core:sync"

// Store is a thread-safe in-memory map from key to value bytes.
// Keys and values are owned by the store's allocator.
Store :: struct {
	mu:        sync.RW_Mutex,
	entries:   map[string][]byte,
}

store_init :: proc(s: ^Store, allocator := context.allocator) {
	s.entries = make(map[string][]byte, allocator)
}

store_destroy :: proc(s: ^Store) {
	for k, v in s.entries {
		delete(k, s.entries.allocator)
		delete(v, s.entries.allocator)
	}
	delete(s.entries)
}

// store_put stores a copy of value under key. Returns true if the key was new.
store_put :: proc(s: ^Store, key: string, value: []byte) -> (created: bool) {
	alloc := s.entries.allocator
	val := slice.clone(value, alloc)

	sync.rw_mutex_lock(&s.mu)
	defer sync.rw_mutex_unlock(&s.mu)

	if old, ok := &s.entries[key]; ok {
		delete(old^, alloc)
		old^ = val
		return false
	}
	s.entries[strings.clone(key, alloc)] = val
	return true
}

// store_get returns a copy of the value for key, allocated with `allocator`.
store_get :: proc(s: ^Store, key: string, allocator := context.allocator) -> (value: []byte, found: bool) {
	sync.rw_mutex_shared_lock(&s.mu)
	defer sync.rw_mutex_shared_unlock(&s.mu)

	v := s.entries[key] or_return
	return slice.clone(v, allocator), true
}

store_delete :: proc(s: ^Store, key: string) -> (deleted: bool) {
	sync.rw_mutex_lock(&s.mu)
	defer sync.rw_mutex_unlock(&s.mu)

	k, v := delete_key(&s.entries, key)
	if k == "" {
		return false
	}
	delete(k, s.entries.allocator)
	delete(v, s.entries.allocator)
	return true
}

// store_keys returns all keys sorted ascending. Keys are copies owned by `allocator`.
store_keys :: proc(s: ^Store, allocator := context.allocator) -> []string {
	keys: [dynamic]string
	{
		sync.rw_mutex_shared_lock(&s.mu)
		defer sync.rw_mutex_shared_unlock(&s.mu)

		keys = make([dynamic]string, 0, len(s.entries), allocator)
		for k in s.entries {
			append(&keys, strings.clone(k, allocator))
		}
	}
	slice.sort(keys[:])
	return keys[:]
}
