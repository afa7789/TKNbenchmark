//! In-memory key-value store holding raw byte values.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// A thread-safe key-value store. Keys are kept in sorted order.
#[derive(Debug, Default)]
pub struct KvStore {
    data: RwLock<BTreeMap<String, Bytes>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores a value; returns `true` if the key was newly created.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        let mut data = self.data.write().unwrap_or_else(PoisonError::into_inner);
        data.insert(key.to_owned(), value).is_none()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        let data = self.data.read().unwrap_or_else(PoisonError::into_inner);
        data.get(key).cloned()
    }

    /// Removes a key; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        let mut data = self.data.write().unwrap_or_else(PoisonError::into_inner);
        data.remove(key).is_some()
    }

    /// All keys sorted ascending.
    pub fn keys(&self) -> Vec<String> {
        let data = self.data.read().unwrap_or_else(PoisonError::into_inner);
        data.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crud_and_sorted_keys() {
        let store = KvStore::new();
        assert!(store.put("b", Bytes::from_static(b"2")));
        assert!(store.put("a", Bytes::from_static(b"1")));
        assert!(!store.put("a", Bytes::from_static(b"3")));
        assert_eq!(store.get("a").as_deref(), Some(&b"3"[..]));
        assert_eq!(store.keys(), ["a", "b"]);
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }
}
