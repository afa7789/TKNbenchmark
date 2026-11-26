//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// Outcome of [`Store::put`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PutOutcome {
    /// The key did not exist before.
    Created,
    /// An existing value was replaced.
    Replaced,
}

/// Keys are kept ordered so listing needs no extra sort. Values are
/// reference-counted [`Bytes`], so readers clone a handle under the lock and
/// transmit it afterwards; the lock is never held during network I/O.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn put(&self, key: &str, value: Bytes) -> PutOutcome {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        match entries.insert(key.to_owned(), value) {
            None => PutOutcome::Created,
            Some(_) => PutOutcome::Replaced,
        }
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.get(key).cloned()
    }

    /// Returns `true` if the key existed and was removed.
    pub fn delete(&self, key: &str) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.remove(key).is_some()
    }

    /// Every key, sorted ascending by byte value.
    pub fn keys(&self) -> Vec<String> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crud() {
        let store = Store::new();
        assert_eq!(
            store.put("a", Bytes::from_static(b"1")),
            PutOutcome::Created
        );
        assert_eq!(
            store.put("a", Bytes::from_static(b"2")),
            PutOutcome::Replaced
        );
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }

    #[test]
    fn keys_are_sorted_by_byte_value() {
        let store = Store::new();
        for key in ["b", "_", "B", "a", "-", "0"] {
            store.put(key, Bytes::new());
        }
        assert_eq!(store.keys(), ["-", "0", "B", "_", "a", "b"]);
    }
}
