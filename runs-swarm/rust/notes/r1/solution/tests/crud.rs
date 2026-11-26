//! `PUT /notes/{id}` and `DELETE /notes/{id}`.

mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;

use common::{TestApp, assert_bad_request};

#[tokio::test]
async fn put_replaces_the_whole_note() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"old","body":"text","tags":["x"]}"#)
        .await;

    let response = app
        .put("/notes/1", r#"{"title":"  new  ","tags":["b","a","b"]}"#)
        .await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    let expected = json!({"id": 1, "title": "new", "body": "", "tags": ["a", "b"]});
    assert_eq!(response.json(), expected);
    assert_eq!(app.get("/notes/1").await.json(), expected);

    // Omitted tags clear them.
    let response = app.put("/notes/1", r#"{"title":"t","body":"b"}"#).await;
    assert_eq!(
        response.json(),
        json!({"id": 1, "title": "t", "body": "b", "tags": []})
    );
}

#[tokio::test]
async fn put_rejects_invalid_bodies_without_changes() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"keep","tags":["x"]}"#).await;
    for body in [
        r#"{"title": "#,
        "",
        "[]",
        "{}",
        r#"{"title":""}"#,
        r#"{"title":"   "}"#,
        r#"{"title":"x","tags":["Bad"]}"#,
        r#"{"title":"x","tags":"x"}"#,
        r#"{"title":"x","body":3}"#,
    ] {
        assert_bad_request(&app.put("/notes/1", body).await);
    }
    assert_eq!(
        app.get("/notes/1").await.json(),
        json!({"id": 1, "title": "keep", "body": "", "tags": ["x"]})
    );
}

#[tokio::test]
async fn put_and_delete_of_unknown_ids_are_not_found() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"a"}"#).await;
    for uri in [
        "/notes/9",
        "/notes/0",
        "/notes/-1",
        "/notes/abc",
        "/notes/1.5",
    ] {
        let response = app.put(uri, r#"{"title":"x"}"#).await;
        assert_eq!(response.status, StatusCode::NOT_FOUND, "PUT {uri}");
        assert!(response.json()["error"].is_string());

        let response = app.delete(uri).await;
        assert_eq!(response.status, StatusCode::NOT_FOUND, "DELETE {uri}");
        assert!(response.json()["error"].is_string());
    }
}

#[tokio::test]
async fn delete_removes_the_note_and_ids_are_not_reused() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"a","tags":["x"]}"#).await;
    app.post("/notes", r#"{"title":"b"}"#).await;

    let response = app.delete("/notes/2").await;
    assert_eq!(response.status, StatusCode::NO_CONTENT);
    assert!(response.body.is_empty());

    assert_eq!(app.get("/notes/2").await.status, StatusCode::NOT_FOUND);
    assert_eq!(app.delete("/notes/2").await.status, StatusCode::NOT_FOUND);
    assert_eq!(
        app.put("/notes/2", r#"{"title":"x"}"#).await.status,
        StatusCode::NOT_FOUND
    );
    assert_eq!(app.get("/notes/1").await.status, StatusCode::OK);

    let app = app.restart();
    assert_eq!(app.post("/notes", r#"{"title":"c"}"#).await.json()["id"], 3);
}

#[tokio::test]
async fn delete_on_collection_is_not_allowed() {
    let app = TestApp::new();
    let response = app.request(Method::DELETE, "/notes", None).await;
    assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED);
    let response = app.request(Method::PUT, "/notes", Some("{}")).await;
    assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED);
}
