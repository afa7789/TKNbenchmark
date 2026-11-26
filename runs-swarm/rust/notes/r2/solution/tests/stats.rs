mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn empty() {
    let app = TestApp::new();
    let response = app.get("/stats").await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    assert_eq!(response.json(), json!({"notes": 0, "tags": {}}));

    let response = app.get("/tags").await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    assert_eq!(response.json(), json!({"tags": []}));
}

#[tokio::test]
async fn counts_tags_and_survives_restart() {
    let mut app = TestApp::new();
    app.create(json!({"title": "a", "tags": ["x", "y", "x"]}))
        .await;
    app.create(json!({"title": "b", "tags": ["x", "b"]})).await;
    app.create(json!({"title": "c", "tags": ["a"]})).await;
    app.create(json!({"title": "d"})).await;

    let stats = json!({"notes": 4, "tags": {"a": 1, "b": 1, "x": 2, "y": 1}});
    let tags = json!({"tags": [
        {"tag": "x", "count": 2},
        {"tag": "a", "count": 1},
        {"tag": "b", "count": 1},
        {"tag": "y", "count": 1},
    ]});
    assert_eq!(app.get("/stats").await.json(), stats);
    assert_eq!(app.get("/tags").await.json(), tags);

    app.restart();
    assert_eq!(app.get("/stats").await.json(), stats);
    assert_eq!(app.get("/tags").await.json(), tags);
}

#[tokio::test]
async fn failed_creates_do_not_count() {
    let app = TestApp::new();
    let response = app.post("/notes", r#"{"title":"","tags":["x"]}"#).await;
    assert_eq!(response.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        app.get("/stats").await.json(),
        json!({"notes": 0, "tags": {}})
    );
}

#[tokio::test]
async fn other_methods_are_not_allowed() {
    let app = TestApp::new();
    for path in ["/stats", "/tags"] {
        for method in [Method::POST, Method::PUT, Method::DELETE] {
            let response = app.request(method.clone(), path, None).await;
            assert_eq!(
                response.status,
                StatusCode::METHOD_NOT_ALLOWED,
                "{method} {path}"
            );
        }
    }
}
