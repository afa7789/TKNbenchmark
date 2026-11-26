//! Thread-safe in-memory key-value store backed by a sorted map.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use axum::body::Bytes;

/// Outcome of [`Store::put`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PutOutcome {
    Created,
    Replaced,
}

/// An in-memory map from keys to byte values, kept sorted by key.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the value stored under `key`, if any.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.read().get(key).cloned()
    }

    /// Stores `value` under `key`, reporting whether the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> PutOutcome {
        match self.write().insert(key.to_owned(), value) {
            Some(_) => PutOutcome::Replaced,
            None => PutOutcome::Created,
        }
    }

    /// Removes `key`, returning whether it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    /// Returns every key, sorted ascending.
    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, BTreeMap<String, Bytes>> {
        self.entries.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, BTreeMap<String, Bytes>> {
        self.entries.write().unwrap_or_else(PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_delete_list() {
        let store = Store::new();
        assert_eq!(store.put("b", Bytes::from_static(b"2")), PutOutcome::Created);
        assert_eq!(store.put("a", Bytes::from_static(b"1")), PutOutcome::Created);
        assert_eq!(store.put("a", Bytes::from_static(b"x")), PutOutcome::Replaced);
        assert_eq!(store.get("a").as_deref(), Some(&b"x"[..]));
        assert_eq!(store.keys(), ["a", "b"]);
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }
}
