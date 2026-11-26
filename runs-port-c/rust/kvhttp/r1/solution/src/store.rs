//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{Arc, PoisonError, RwLock};

/// Whether a `put` created a new entry or replaced an existing one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PutOutcome {
    Created,
    Replaced,
}

/// An in-memory map from keys to byte values, guarded by a reader-writer lock.
///
/// Values are reference-counted so readers can hand them out without copying
/// while holding the lock. Keys are kept ordered, so listing is a plain walk.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Arc<[u8]>>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn put(&self, key: &str, value: impl Into<Arc<[u8]>>) -> PutOutcome {
        let value = value.into();
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        match entries.get_mut(key) {
            Some(slot) => {
                *slot = value;
                PutOutcome::Replaced
            }
            None => {
                entries.insert(key.to_owned(), value);
                PutOutcome::Created
            }
        }
    }

    pub fn get(&self, key: &str) -> Option<Arc<[u8]>> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.get(key).cloned()
    }

    /// Removes `key`, returning whether it was present.
    pub fn delete(&self, key: &str) -> bool {
        let removed = {
            let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
            entries.remove(key)
        };
        // The value (possibly large) is dropped here, outside the lock.
        removed.is_some()
    }

    /// Returns a snapshot of all keys in ascending order.
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
        let s = Store::new();
        assert_eq!(s.put("a", b"1".as_slice()), PutOutcome::Created);
        assert_eq!(s.put("a", b"2".as_slice()), PutOutcome::Replaced);
        assert_eq!(s.get("a").as_deref(), Some(b"2".as_slice()));
        assert!(s.delete("a"));
        assert!(!s.delete("a"));
        assert!(s.get("a").is_none());
    }

    #[test]
    fn keys_sorted() {
        let s = Store::new();
        for k in ["b", "a", "C", "_", "-"] {
            s.put(k, Vec::new());
        }
        assert_eq!(s.keys(), ["-", "C", "_", "a", "b"]);
    }
}
