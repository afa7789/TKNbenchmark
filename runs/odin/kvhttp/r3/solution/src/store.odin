package kvhttp

import "base:runtime"
import "core:slice"
import "core:strings"
import "core:sync"

// Store is a thread-safe in-memory key-value map. Keys and values are owned by
// the store and live in `allocator`, which must be safe for concurrent use.
Store :: struct {
	lock:      sync.RW_Mutex,
	entries:   map[string][]byte,
	allocator: runtime.Allocator,
}

store_init :: proc(s: ^Store, allocator := context.allocator) {
	s.allocator = allocator
	s.entries = make(map[string][]byte, allocator = allocator)
}

store_destroy :: proc(s: ^Store) {
	for k, v in s.entries {
		delete(k, s.allocator)
		delete(v, s.allocator)
	}
	delete(s.entries)
	s^ = {}
}

// store_put takes ownership of `value`, which must have been allocated with the
// store's allocator, even on failure. Returns true if the key did not exist before.
store_put :: proc(s: ^Store, key: string, value: []byte) -> (created: bool, err: runtime.Allocator_Error) {
	sync.guard(&s.lock)

	key_ptr, value_ptr, just_inserted, map_err := map_entry(&s.entries, key)
	if map_err != nil {
		delete(value, s.allocator)
		return false, map_err
	}
	if just_inserted {
		owned_key, clone_err := strings.clone(key, s.allocator)
		if clone_err != nil {
			delete_key(&s.entries, key)
			delete(value, s.allocator)
			return false, clone_err
		}
		key_ptr^ = owned_key
	} else {
		delete(value_ptr^, s.allocator)
	}
	value_ptr^ = value
	return just_inserted, nil
}

// store_get returns a copy of the stored value allocated with `allocator`.
store_get :: proc(s: ^Store, key: string, allocator := context.allocator) -> (value: []byte, found: bool) {
	sync.shared_guard(&s.lock)

	stored := s.entries[key] or_return
	return slice.clone(stored, allocator), true
}

store_delete :: proc(s: ^Store, key: string) -> (deleted: bool) {
	sync.guard(&s.lock)

	if key not_in s.entries {
		return false
	}
	k, v := delete_key(&s.entries, key)
	delete(k, s.allocator)
	delete(v, s.allocator)
	return true
}

// store_keys returns every key sorted ascending; the strings are copies owned
// by the caller, allocated with `allocator`.
store_keys :: proc(s: ^Store, allocator := context.allocator) -> []string {
	keys: []string
	{
		sync.shared_guard(&s.lock)
		keys = make([]string, len(s.entries), allocator)
		i := 0
		for k in s.entries {
			keys[i] = strings.clone(k, allocator)
			i += 1
		}
	}
	slice.sort(keys)
	return keys
}
