//! Thread-safe in-memory key-value store. Keys are kept sorted so listing
//! is a cheap traversal.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use axum::body::Bytes;

/// Outcome of a [`Store::put`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PutOutcome {
    Created,
    Replaced,
}

#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`, reporting whether the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> PutOutcome {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        match entries.insert(key.to_owned(), value) {
            Some(_) => PutOutcome::Replaced,
            None => PutOutcome::Created,
        }
    }

    /// Returns the value stored under `key`, if any.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.get(key).cloned()
    }

    /// Removes `key`, returning whether it was present.
    pub fn delete(&self, key: &str) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.remove(key).is_some()
    }

    /// Returns all keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.keys().cloned().collect()
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
