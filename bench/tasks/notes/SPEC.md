# notes

An HTTP service `./app <port>`: a small notes store backed by SQLite.

- Listen on `127.0.0.1:<port>`. Answer `GET /health` with status 200 and the body `ok` as soon as you accept
  requests.
- Keep all data in a **SQLite** database at the path given by the environment variable `NOTES_DB`; create
  the file and the schema if they do not exist. The data must survive a restart of the program with the same
  `NOTES_DB`.
- Third-party packages are allowed (an HTTP framework, a JSON library, a SQLite binding, or the system's
  SQLite library).
- Request and response bodies are JSON (`Content-Type: application/json`) except `/health`.
- The server must handle concurrent requests.

## Notes

A note is `{"id": <int>, "title": <string>, "body": <string>, "tags": [<string>, ...]}`.

- `id` is assigned by the server: 1, 2, 3, … in creation order. An id is never reused, also after a delete
  or a restart.
- `title`: required, a string of 1–200 characters after removing leading and trailing spaces; stored
  without them.
- `body`: optional string, default `""`.
- `tags`: optional array of strings, default `[]`. Each tag is 1–32 characters from `a-z`, `0-9` and `-`.
  Duplicates are removed and the tags are stored sorted ascending.

## Endpoints

| Request | Success | Errors |
|---|---|---|
| `POST /notes` with `{title, body?, tags?}` | 201 and the created note | 400 |
| `GET /notes/{id}` | 200 and the note | 404 |
| `PUT /notes/{id}` with `{title, body?, tags?}` (full replacement: an omitted `body` or `tags` becomes `""` or `[]`) | 200 and the updated note | 400, 404 |
| `DELETE /notes/{id}` | 204, empty body | 404 |
| `GET /notes` | 200 and `{"notes": [note, ...]}` ordered by id ascending | 400 |
| `GET /stats` | 200 and `{"notes": <count>, "tags": {"<tag>": <count>, ...}}` | |
| `GET /tags` | 200 and `{"tags": [{"tag": "<tag>", "count": <n>}, ...]}` ordered by count descending, then tag ascending | |

`GET /notes` takes optional query parameters, all combinable:

- `tag=<tag>`: only notes that have this tag.
- `q=<text>`: only notes whose title or body contains the text, ignoring ASCII case.
- `after=<id>`: only notes with an id greater than this integer.
- `limit=<n>`: at most `n` notes, `1 ≤ n ≤ 100`; default 100.

In `/stats` and `/tags`, a tag counts the notes that have it; tags of deleted notes no longer count.

## Errors

- 400 with a JSON body `{"error": "<message>"}`: a body that is not valid JSON or not an object, a missing
  or invalid `title`, a `body` that is not a string, invalid `tags`, or an invalid `limit` or `after`.
- 404: an unknown path, or a note id that does not exist or is not a positive integer.
- 405: a known path with a method it does not support (for example `DELETE /notes`).
