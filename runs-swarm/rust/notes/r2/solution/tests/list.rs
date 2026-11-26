mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::{Value, json};

async fn ids(app: &TestApp, uri: &str) -> Vec<i64> {
    let response = app.get(uri).await;
    assert_eq!(
        response.status,
        StatusCode::OK,
        "{uri}: {}",
        response.text()
    );
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    response.json()["notes"]
        .as_array()
        .expect("notes array")
        .iter()
        .map(|note| note["id"].as_i64().expect("id"))
        .collect()
}

#[tokio::test]
async fn lists_full_notes_in_id_order() {
    let app = TestApp::new();
    assert_eq!(app.get("/notes").await.json(), json!({"notes": []}));
    let a = app.create(json!({"title": "a", "tags": ["z", "b"]})).await;
    let b = app.create(json!({"title": "b", "body": "x"})).await;
    assert_eq!(app.get("/notes").await.json(), json!({"notes": [a, b]}));
}

#[tokio::test]
async fn filters_and_paging() {
    let app = TestApp::new();
    app.create(json!({"title": "Hello world", "tags": ["greet"]}))
        .await;
    app.create(json!({"title": "other", "body": "say HELLO", "tags": ["greet", "misc"]}))
        .await;
    app.create(json!({"title": "nothing"})).await;
    app.create(json!({"title": "50% off", "body": "a b"})).await;

    assert_eq!(ids(&app, "/notes?tag=misc").await, [2]);
    assert_eq!(ids(&app, "/notes?tag=Bad%20Tag").await, Vec::<i64>::new());
    assert_eq!(ids(&app, "/notes?q=hello").await, [1, 2]);
    assert_eq!(ids(&app, "/notes?q=HeLLo&tag=misc").await, [2]);
    assert_eq!(ids(&app, "/notes?q=50%25").await, [4]);
    assert_eq!(ids(&app, "/notes?q=a+b").await, [4]);
    assert_eq!(ids(&app, "/notes?q=").await, [1, 2, 3, 4]);
    assert_eq!(ids(&app, "/notes?limit=2").await, [1, 2]);
    assert_eq!(ids(&app, "/notes?after=2&limit=1").await, [3]);
    assert_eq!(ids(&app, "/notes?after=0").await, [1, 2, 3, 4]);
    assert_eq!(ids(&app, "/notes?after=-1").await, [1, 2, 3, 4]);
    assert_eq!(ids(&app, "/notes?after=4").await, Vec::<i64>::new());
    assert_eq!(
        ids(&app, "/notes?tag=greet&after=1&q=o&limit=100").await,
        [2]
    );
    assert_eq!(ids(&app, "/notes?unknown=1").await, [1, 2, 3, 4]);
}

#[tokio::test]
async fn default_limit_is_100() {
    let app = TestApp::new();
    for i in 0..105 {
        app.create(json!({"title": format!("n{i}")})).await;
    }
    assert_eq!(ids(&app, "/notes").await.len(), 100);
    assert_eq!(
        ids(&app, "/notes?after=100").await,
        [101, 102, 103, 104, 105]
    );
}

#[tokio::test]
async fn rejects_invalid_limit_and_after() {
    let app = TestApp::new();
    for query in [
        "limit=0",
        "limit=101",
        "limit=-1",
        "limit=abc",
        "limit=",
        "limit=1.5",
        "after=abc",
        "after=",
        "after=1.5",
        "after=%201",
    ] {
        let response = app.get(&format!("/notes?{query}")).await;
        assert_eq!(response.status, StatusCode::BAD_REQUEST, "{query}");
        assert!(
            matches!(response.json()["error"], Value::String(_)),
            "{query}"
        );
    }
}

#[tokio::test]
async fn other_methods_are_not_allowed() {
    let app = TestApp::new();
    for method in [Method::DELETE, Method::PATCH] {
        let response = app.request(method.clone(), "/notes", None).await;
        assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED, "{method}");
    }
}
