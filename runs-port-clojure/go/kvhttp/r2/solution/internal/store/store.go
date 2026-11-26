// Package store provides a thread-safe in-memory key-value store.
package store

import (
	"slices"
	"sync"
)

// Store is a concurrency-safe map from keys to byte values.
// The zero value is not usable; create one with New.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// New returns an empty store.
func New() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Put stores value under key. It reports whether the key was newly created
// (true) or an existing value was replaced (false). The store takes
// ownership of value; callers must not modify it afterwards.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, existed := s.data[key]
	s.data[key] = value
	return !existed
}

// Get returns the value stored under key and whether it was present.
// The returned slice must not be modified.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.data[key]
	return v, ok
}

// Delete removes key and reports whether it was present.
func (s *Store) Delete(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.data[key]
	delete(s.data, key)
	return ok
}

// Keys returns all keys in ascending order.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := make([]string, 0, len(s.data))
	for k := range s.data {
		keys = append(keys, k)
	}
	s.mu.RUnlock()
	slices.Sort(keys)
	return keys
}
