//! Updating and deleting notes (`PUT` and `DELETE /notes/{id}`).

use rusqlite::{TransactionBehavior, params};

use super::notes::insert_tags;
use super::{Result, Store};
use crate::model::{Note, NoteInput};

impl Store {
    /// Replaces the title, body and tags of the note with `id`. Returns the updated note, or
    /// `None` if it does not exist.
    pub async fn update_note(&self, id: i64, input: NoteInput) -> Result<Option<Note>> {
        self.call(move |conn| {
            let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
            let updated = tx.execute(
                "UPDATE notes SET title = ?1, body = ?2 WHERE id = ?3",
                params![input.title, input.body, id],
            )?;
            if updated == 0 {
                return Ok(None);
            }
            tx.execute("DELETE FROM note_tags WHERE note_id = ?1", [id])?;
            insert_tags(&tx, id, &input.tags)?;
            tx.commit()?;
            Ok(Some(Note {
                id,
                title: input.title,
                body: input.body,
                tags: input.tags,
            }))
        })
        .await
    }

    /// Deletes the note with `id` and its tags. Returns whether it existed.
    pub async fn delete_note(&self, id: i64) -> Result<bool> {
        self.call(move |conn| {
            let deleted = conn.execute("DELETE FROM notes WHERE id = ?1", [id])?;
            Ok(deleted > 0)
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use crate::model::NoteInput;
    use crate::store::test_support::TempStore;

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: format!("body of {title}"),
            tags: tags.iter().map(|t| t.to_string()).collect(),
        }
    }

    #[tokio::test]
    async fn update_replaces_fields_and_tags() {
        let db = TempStore::new();
        let note = db.store.create_note(input("a", &["x", "y"])).await.unwrap();
        let updated = db
            .store
            .update_note(note.id, input("b", &["y", "z"]))
            .await
            .unwrap()
            .expect("note exists");
        assert_eq!(updated.id, note.id);
        assert_eq!(updated.tags, ["y", "z"]);
        assert_eq!(db.store.get_note(note.id).await.unwrap(), Some(updated));
    }

    #[tokio::test]
    async fn update_missing_note() {
        let db = TempStore::new();
        assert_eq!(
            db.store.update_note(1, input("a", &[])).await.unwrap(),
            None
        );
    }

    #[tokio::test]
    async fn delete_removes_note_and_ids_are_not_reused() {
        let db = TempStore::new();
        let a = db.store.create_note(input("a", &["t"])).await.unwrap();
        assert!(db.store.delete_note(a.id).await.unwrap());
        assert!(!db.store.delete_note(a.id).await.unwrap());
        assert_eq!(db.store.get_note(a.id).await.unwrap(), None);
        let b = db.store.create_note(input("b", &[])).await.unwrap();
        assert_eq!(b.id, a.id + 1);
    }
}
