//! Thread-safe in-memory store keeping keys in ascending order.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

#[derive(Debug, Default)]
pub struct KvStore {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores the value; returns `true` if the key was newly created.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.entries
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .insert(key.to_owned(), value)
            .is_none()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.entries
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .get(key)
            .cloned()
    }

    /// Removes the key; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.entries
            .write()
            .unwrap_or_else(PoisonError::into_inner)
            .remove(key)
            .is_some()
    }

    /// All keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        self.entries
            .read()
            .unwrap_or_else(PoisonError::into_inner)
            .keys()
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_delete() {
        let store = KvStore::new();
        assert!(store.put("a", Bytes::from_static(b"1")));
        assert!(!store.put("a", Bytes::from_static(b"2")));
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }

    #[test]
    fn keys_are_sorted() {
        let store = KvStore::new();
        for key in ["b", "a", "c", "B"] {
            store.put(key, Bytes::new());
        }
        assert_eq!(store.keys(), ["B", "a", "b", "c"]);
    }
}
