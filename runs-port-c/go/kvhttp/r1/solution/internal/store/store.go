// Package store provides a thread-safe in-memory key-value store.
package store

import (
	"maps"
	"slices"
	"sync"
)

// Store maps string keys to byte values. The zero value is not usable; call New.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// New returns an empty store.
func New() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Put stores value under key, taking ownership of the slice.
// It reports whether the key was newly created.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, exists := s.data[key]
	s.data[key] = value
	return !exists
}

// Get returns the value stored under key. The returned slice must not be modified.
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
	if _, ok := s.data[key]; !ok {
		return false
	}
	delete(s.data, key)
	return true
}

// Keys returns all keys sorted ascending. The result is never nil.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := make([]string, 0, len(s.data))
	keys = slices.AppendSeq(keys, maps.Keys(s.data))
	s.mu.RUnlock()
	slices.Sort(keys)
	return keys
}
