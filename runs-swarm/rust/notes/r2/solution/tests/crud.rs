mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn update_replaces_the_note() {
    let app = TestApp::new();
    app.create(json!({"title": "old", "body": "text", "tags": ["x"]}))
        .await;

    let response = app
        .request(
            Method::PUT,
            "/notes/1",
            Some(r#"{"title":"  new ","tags":["b","a","b"]}"#),
        )
        .await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    let expected = json!({"id": 1, "title": "new", "body": "", "tags": ["a", "b"]});
    assert_eq!(response.json(), expected);
    assert_eq!(app.get("/notes/1").await.json(), expected);
}

#[tokio::test]
async fn update_errors() {
    let app = TestApp::new();
    let original = app.create(json!({"title": "keep", "tags": ["x"]})).await;

    for body in [
        "",
        "{\"title\": ",
        "[]",
        "{}",
        "{\"title\":\"\"}",
        "{\"title\":\"x\",\"body\":null}",
        "{\"title\":\"x\",\"tags\":[\"Bad\"]}",
        "{\"title\":\"x\",\"tags\":\"x\"}",
    ] {
        let response = app.request(Method::PUT, "/notes/1", Some(body)).await;
        assert_eq!(response.status, StatusCode::BAD_REQUEST, "{body:?}");
        assert!(response.json()["error"].is_string(), "{body:?}");
    }
    assert_eq!(app.get("/notes/1").await.json(), original, "unchanged");

    for uri in ["/notes/9", "/notes/0", "/notes/-1", "/notes/abc"] {
        let response = app
            .request(Method::PUT, uri, Some(r#"{"title":"t"}"#))
            .await;
        assert_eq!(response.status, StatusCode::NOT_FOUND, "{uri}");
    }
}

#[tokio::test]
async fn delete_removes_the_note() {
    let mut app = TestApp::new();
    app.create(json!({"title": "a", "tags": ["x"]})).await;
    app.create(json!({"title": "b"})).await;

    let response = app.request(Method::DELETE, "/notes/2", None).await;
    assert_eq!(response.status, StatusCode::NO_CONTENT);
    assert!(response.body.is_empty());
    assert_eq!(app.get("/notes/2").await.status, StatusCode::NOT_FOUND);
    assert_eq!(
        app.request(Method::DELETE, "/notes/2", None).await.status,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        app.request(Method::PUT, "/notes/2", Some(r#"{"title":"t"}"#))
            .await
            .status,
        StatusCode::NOT_FOUND
    );
    assert_eq!(app.get("/notes/1").await.status, StatusCode::OK);

    // Ids are never reused, also after a restart.
    app.restart();
    assert_eq!(app.create(json!({"title": "c"})).await["id"], 3);
}

#[tokio::test]
async fn delete_unknown_ids() {
    let app = TestApp::new();
    for uri in ["/notes/1", "/notes/0", "/notes/x"] {
        let response = app.request(Method::DELETE, uri, None).await;
        assert_eq!(response.status, StatusCode::NOT_FOUND, "{uri}");
    }
}

#[tokio::test]
async fn unsupported_methods() {
    let app = TestApp::new();
    for (method, uri) in [(Method::DELETE, "/notes"), (Method::PATCH, "/notes/1")] {
        let response = app.request(method, uri, None).await;
        assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED, "{uri}");
    }
}
