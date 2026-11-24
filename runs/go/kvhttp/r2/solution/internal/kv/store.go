// Package kv implements an in-memory key-value store and its HTTP API.
package kv

import (
	"slices"
	"sync"
)

// Store is a concurrency-safe in-memory map from keys to byte values.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// NewStore returns an empty Store.
func NewStore() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Get returns the value stored under key. The returned slice must not be modified.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.data[key]
	return v, ok
}

// Put stores value under key, taking ownership of value. It reports whether
// the key was newly created.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, existed := s.data[key]
	s.data[key] = value
	return !existed
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

// Keys returns all keys in ascending order. The result is never nil.
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
