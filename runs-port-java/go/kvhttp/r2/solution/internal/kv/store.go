// Package kv implements the in-memory key-value store and its HTTP API.
package kv

import (
	"slices"
	"sync"
)

// Store is a concurrency-safe in-memory map from keys to byte values.
type Store struct {
	mu      sync.RWMutex
	entries map[string][]byte
}

// NewStore returns an empty Store.
func NewStore() *Store {
	return &Store{entries: make(map[string][]byte)}
}

// Put stores value under key and reports whether the key was newly created.
// The store takes ownership of value; callers must not modify it afterwards.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
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

// Keys returns every key in ascending order.
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
