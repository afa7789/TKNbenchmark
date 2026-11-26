//! In-memory key-value store. Keys are kept sorted so listing is cheap.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// A thread-safe, sorted, in-memory map from keys to byte values.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    /// Returns a new, empty store.
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`. Returns `true` if the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.insert(key.to_owned(), value).is_none()
    }

    /// Returns the value stored under `key`, if any.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.get(key).cloned()
    }

    /// Removes `key`. Returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.remove(key).is_some()
    }

    /// Returns every key in ascending order.
    pub fn keys(&self) -> Vec<String> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_delete() {
        let store = Store::new();
        assert!(store.put("a", Bytes::from_static(b"1")));
        assert!(!store.put("a", Bytes::from_static(b"2")));
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }

    #[test]
    fn keys_are_sorted() {
        let store = Store::new();
        for k in ["b", "a", "c"] {
            store.put(k, Bytes::new());
        }
        assert_eq!(store.keys(), ["a", "b", "c"]);
    }
}
