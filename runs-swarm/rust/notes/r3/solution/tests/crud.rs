mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn update_is_full_replacement() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"old","body":"text","tags":["x"]}"#)
        .await;

    let res = app
        .request(
            Method::PUT,
            "/notes/1",
            Some(r#"{"title":"  new ","tags":["b","a","b"]}"#),
        )
        .await;
    let expected = json!({"id": 1, "title": "new", "body": "", "tags": ["a", "b"]});
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.content_type.as_deref(), Some("application/json"));
    assert_eq!(res.json(), expected);
    assert_eq!(app.get("/notes/1").await.json(), expected);
}

#[tokio::test]
async fn update_errors() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"a","tags":["keep"]}"#).await;

    for body in [
        "not json",
        "[]",
        "{}",
        r#"{"title":""}"#,
        r#"{"title":"x","body":1}"#,
        r#"{"title":"x","tags":["Bad"]}"#,
    ] {
        let res = app.request(Method::PUT, "/notes/1", Some(body)).await;
        assert_eq!(res.status, StatusCode::BAD_REQUEST, "{body}");
        assert!(res.json()["error"].is_string(), "{body}");
    }
    // Rejected updates leave the note unchanged.
    assert_eq!(
        app.get("/notes/1").await.json(),
        json!({"id": 1, "title": "a", "body": "", "tags": ["keep"]})
    );

    for uri in ["/notes/2", "/notes/0", "/notes/abc"] {
        let res = app
            .request(Method::PUT, uri, Some(r#"{"title":"x"}"#))
            .await;
        assert_eq!(res.status, StatusCode::NOT_FOUND, "{uri}");
        assert!(res.json()["error"].is_string(), "{uri}");
    }
}

#[tokio::test]
async fn delete() {
    let app = TestApp::new();
    app.post("/notes", r#"{"title":"a"}"#).await;
    app.post("/notes", r#"{"title":"b"}"#).await;

    let res = app.request(Method::DELETE, "/notes/2", None).await;
    assert_eq!(res.status, StatusCode::NO_CONTENT);
    assert!(res.body.is_empty());
    assert_eq!(app.get("/notes/2").await.status, StatusCode::NOT_FOUND);
    assert_eq!(app.get("/notes/1").await.status, StatusCode::OK);

    for uri in ["/notes/2", "/notes/0", "/notes/x"] {
        let res = app.request(Method::DELETE, uri, None).await;
        assert_eq!(res.status, StatusCode::NOT_FOUND, "{uri}");
        assert!(res.json()["error"].is_string(), "{uri}");
    }

    // Ids are never reused, even for the highest deleted id.
    let res = app.post("/notes", r#"{"title":"c"}"#).await;
    assert_eq!(res.json()["id"], 3);
}
