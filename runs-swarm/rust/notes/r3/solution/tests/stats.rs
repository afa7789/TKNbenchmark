mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn empty() {
    let app = TestApp::new();
    let res = app.get("/stats").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.content_type.as_deref(), Some("application/json"));
    assert_eq!(res.json(), json!({"notes": 0, "tags": {}}));

    let res = app.get("/tags").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.content_type.as_deref(), Some("application/json"));
    assert_eq!(res.json(), json!({"tags": []}));
}

#[tokio::test]
async fn counts_notes_per_tag() {
    let app = TestApp::new();
    for body in [
        r#"{"title":"a","tags":["x","y"]}"#,
        r#"{"title":"b","tags":["x","x"]}"#,
        r#"{"title":"c"}"#,
        r#"{"title":"d","tags":["a-1","y","x"]}"#,
    ] {
        assert_eq!(app.post("/notes", body).await.status, StatusCode::CREATED);
    }

    let res = app.get("/stats").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(
        res.json(),
        json!({"notes": 4, "tags": {"x": 3, "y": 2, "a-1": 1}})
    );

    let res = app.get("/tags").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(
        res.json(),
        json!({"tags": [
            {"tag": "x", "count": 3},
            {"tag": "y", "count": 2},
            {"tag": "a-1", "count": 1},
        ]})
    );
}

#[tokio::test]
async fn other_methods_are_not_allowed() {
    let app = TestApp::new();
    for uri in ["/stats", "/tags"] {
        for method in [Method::POST, Method::PUT, Method::DELETE] {
            let res = app.request(method.clone(), uri, Some("{}")).await;
            assert_eq!(res.status, StatusCode::METHOD_NOT_ALLOWED, "{method} {uri}");
        }
    }
}
