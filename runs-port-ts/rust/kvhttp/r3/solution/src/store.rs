//! In-memory key-value store holding raw byte values.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// Thread-safe map from keys to byte values; keys are kept sorted.
#[derive(Debug, Default)]
pub struct KvStore {
    data: RwLock<BTreeMap<String, Bytes>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.read().get(key).cloned()
    }

    /// Stores `value` under `key`; returns `true` if the key was newly created.
    pub fn set(&self, key: &str, value: Bytes) -> bool {
        self.write().insert(key.to_owned(), value).is_none()
    }

    /// Removes `key`; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    /// All keys, sorted ascending by byte order.
    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }

    // The map holds no invariants a panicking writer could break, so poisoning is ignored.
    fn read(&self) -> std::sync::RwLockReadGuard<'_, BTreeMap<String, Bytes>> {
        self.data.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, BTreeMap<String, Bytes>> {
        self.data.write().unwrap_or_else(PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crud_and_sorted_keys() {
        let store = KvStore::new();
        assert!(store.set("b", Bytes::from_static(b"2")));
        assert!(store.set("a", Bytes::from_static(b"1")));
        assert!(!store.set("a", Bytes::from_static(b"x")));
        assert_eq!(store.get("a").as_deref(), Some(&b"x"[..]));
        assert_eq!(store.keys(), ["a", "b"]);
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }
}
