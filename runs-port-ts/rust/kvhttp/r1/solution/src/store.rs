//! In-memory key-value store. Values are kept as raw bytes.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// A thread-safe map from keys to byte values, ordered by key.
#[derive(Debug, Default)]
pub struct KvStore {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`; returns `true` if the key was newly created.
    pub fn set(&self, key: &str, value: Bytes) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.insert(key.to_owned(), value).is_none()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.get(key).cloned()
    }

    /// Removes `key`; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.remove(key).is_some()
    }

    /// All keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_get_delete() {
        let store = KvStore::new();
        assert!(store.set("b", Bytes::from_static(b"1")));
        assert!(!store.set("b", Bytes::from_static(b"2")));
        assert!(store.set("a", Bytes::new()));
        assert_eq!(store.get("b").as_deref(), Some(&b"2"[..]));
        assert_eq!(store.keys(), ["a", "b"]);
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }
}
