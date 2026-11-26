//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};

use bytes::Bytes;

/// An in-memory map from keys to byte values, safe to share across tasks.
///
/// Keys are kept ordered so listing them is a simple in-order walk.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`. Returns `true` if the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        let mut entries = self.write();
        match entries.get_mut(key) {
            Some(slot) => {
                *slot = value;
                false
            }
            None => {
                entries.insert(key.to_owned(), value);
                true
            }
        }
    }

    /// Returns the value stored under `key`, if any. Cloning `Bytes` is cheap.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.read().get(key).cloned()
    }

    /// Removes `key`. Returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    /// Returns every key in ascending byte order.
    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }

    // A panic while holding the lock cannot leave the map logically
    // inconsistent (every mutation is a single map call), so poisoning is
    // safe to ignore.
    fn read(&self) -> RwLockReadGuard<'_, BTreeMap<String, Bytes>> {
        self.entries.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> RwLockWriteGuard<'_, BTreeMap<String, Bytes>> {
        self.entries.write().unwrap_or_else(PoisonError::into_inner)
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
        for key in ["b", "a", "C", "_", "-", "0"] {
            store.put(key, Bytes::new());
        }
        assert_eq!(store.keys(), ["-", "0", "C", "_", "a", "b"]);
    }
}
