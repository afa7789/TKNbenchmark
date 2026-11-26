mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::json;

#[tokio::test]
async fn health() {
    let app = TestApp::new();
    let response = app.get("/health").await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.text(), "ok");
}

#[tokio::test]
async fn create_and_get() {
    let app = TestApp::new();
    let first = app.create(json!({"title": "first"})).await;
    assert_eq!(
        first,
        json!({"id": 1, "title": "first", "body": "", "tags": []})
    );

    let second = app
        .create(
            json!({"title": "  second  ", "body": "some text", "tags": ["work", "b-2", "work"]}),
        )
        .await;
    let expected =
        json!({"id": 2, "title": "second", "body": "some text", "tags": ["b-2", "work"]});
    assert_eq!(second, expected);

    let response = app.get("/notes/2").await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    assert_eq!(response.json(), expected);
}

#[tokio::test]
async fn create_errors() {
    let app = TestApp::new();
    for body in [
        "{\"title\": ",
        "[]",
        "{}",
        "{\"title\":\"   \"}",
        "{\"title\":\"x\",\"tags\":[\"Bad\"]}",
        "{\"title\":\"x\",\"body\":3}",
        "",
    ] {
        let response = app.post("/notes", body).await;
        assert_eq!(response.status, StatusCode::BAD_REQUEST, "{body:?}");
        assert!(response.json()["error"].is_string(), "{body:?}");
    }
    // Nothing was stored, so the next id is still 1.
    assert_eq!(app.create(json!({"title": "ok"})).await["id"], 1);
}

#[tokio::test]
async fn not_found() {
    let app = TestApp::new();
    app.create(json!({"title": "x"})).await;
    for uri in [
        "/nope",
        "/notes/abc",
        "/notes/0",
        "/notes/-1",
        "/notes/7",
        "/notes/1/x",
    ] {
        let response = app.get(uri).await;
        assert_eq!(response.status, StatusCode::NOT_FOUND, "{uri}");
        assert!(response.json()["error"].is_string(), "{uri}");
    }
}

#[tokio::test]
async fn method_not_allowed() {
    let app = TestApp::new();
    let response = app.request(Method::DELETE, "/health", None).await;
    assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED);
    assert!(response.json()["error"].is_string());
}

#[tokio::test]
async fn data_survives_restart() {
    let mut app = TestApp::new();
    app.create(json!({"title": "kept", "tags": ["t"]})).await;
    app.restart();
    let response = app.get("/notes/1").await;
    assert_eq!(
        response.json(),
        json!({"id": 1, "title": "kept", "body": "", "tags": ["t"]})
    );
    assert_eq!(app.create(json!({"title": "next"})).await["id"], 2);
}

#[tokio::test]
async fn concurrent_creates_get_distinct_ids() {
    let app = std::sync::Arc::new(TestApp::new());
    let tasks: Vec<_> = (0..32)
        .map(|i| {
            let app = app.clone();
            tokio::spawn(async move {
                app.create(json!({"title": format!("n{i}"), "tags": ["c"]}))
                    .await
            })
        })
        .collect();
    let mut ids = Vec::new();
    for task in tasks {
        ids.push(task.await.unwrap()["id"].as_i64().unwrap());
    }
    ids.sort_unstable();
    assert_eq!(ids, (1..=32).collect::<Vec<_>>());
}
