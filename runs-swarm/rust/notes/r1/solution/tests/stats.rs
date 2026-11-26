//! `GET /stats` and `GET /tags`.

mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;

use common::TestApp;

#[tokio::test]
async fn empty() {
    let app = TestApp::new();

    let stats = app.get("/stats").await;
    assert_eq!(stats.status, StatusCode::OK);
    assert_eq!(stats.content_type.as_deref(), Some("application/json"));
    assert_eq!(stats.json(), json!({"notes": 0, "tags": {}}));

    let tags = app.get("/tags").await;
    assert_eq!(tags.status, StatusCode::OK);
    assert_eq!(tags.content_type.as_deref(), Some("application/json"));
    assert_eq!(tags.json(), json!({"tags": []}));
}

#[tokio::test]
async fn counts_notes_per_tag() {
    let app = TestApp::new();
    for body in [
        r#"{"title":"a","tags":["x","y"]}"#,
        r#"{"title":"b","tags":["x","x"]}"#,
        r#"{"title":"c"}"#,
        r#"{"title":"d","tags":["a-1","z"]}"#,
        r#"{"title":"e","tags":["z"]}"#,
    ] {
        assert_eq!(app.post("/notes", body).await.status, StatusCode::CREATED);
    }
    // Rejected notes count for nothing.
    app.post("/notes", r#"{"title":"","tags":["x"]}"#).await;

    assert_eq!(
        app.get("/stats").await.json(),
        json!({"notes": 5, "tags": {"a-1": 1, "x": 2, "y": 1, "z": 2}})
    );
    assert_eq!(
        app.get("/tags").await.json(),
        json!({"tags": [
            {"tag": "x", "count": 2},
            {"tag": "z", "count": 2},
            {"tag": "a-1", "count": 1},
            {"tag": "y", "count": 1},
        ]})
    );

    let app = app.restart();
    assert_eq!(app.get("/stats").await.json()["notes"], 5);
}

#[tokio::test]
async fn other_methods_are_not_allowed() {
    let app = TestApp::new();
    for uri in ["/stats", "/tags"] {
        for method in [Method::POST, Method::PUT, Method::DELETE] {
            let response = app.request(method, uri, Some("{}")).await;
            assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED, "{uri}");
        }
    }
}
