// Package store provides a concurrency-safe in-memory key-value store.
package store

import (
	"slices"
	"sync"
)

// Store maps string keys to raw byte values. The zero value is ready to use.
type Store struct {
	mu      sync.RWMutex
	entries map[string][]byte
}

// New returns an empty Store.
func New() *Store {
	return &Store{entries: make(map[string][]byte)}
}

// Set stores value under key and reports whether the key was newly created.
// The store takes ownership of value; callers must not modify it afterwards.
func (s *Store) Set(key string, value []byte) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.entries == nil {
		s.entries = make(map[string][]byte)
	}
	_, exists := s.entries[key]
	s.entries[key] = value
	return !exists
}

// Get returns the value stored under key and whether it was present.
// The returned slice must not be modified.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.entries[key]
	return v, ok
}

// Delete removes key and reports whether it was present.
func (s *Store) Delete(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.entries[key]
	delete(s.entries, key)
	return ok
}

// Keys returns all keys in ascending order. It never returns nil.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := make([]string, 0, len(s.entries))
	for k := range s.entries {
		keys = append(keys, k)
	}
	s.mu.RUnlock()
	slices.Sort(keys)
	return keys
}
