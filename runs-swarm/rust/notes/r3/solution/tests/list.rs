mod common;

use axum::http::{Method, StatusCode};
use common::TestApp;
use serde_json::{Value, json};

async fn seeded() -> TestApp {
    let app = TestApp::new();
    for body in [
        r#"{"title":"Hello world","tags":["greet"]}"#,
        r#"{"title":"other","body":"say HELLO","tags":["misc","greet"]}"#,
        r#"{"title":"nothing"}"#,
    ] {
        assert_eq!(app.post("/notes", body).await.status, StatusCode::CREATED);
    }
    app
}

async fn list_ids(app: &TestApp, uri: &str) -> Vec<i64> {
    let res = app.get(uri).await;
    assert_eq!(res.status, StatusCode::OK, "{uri}");
    assert_eq!(res.content_type.as_deref(), Some("application/json"));
    res.json()["notes"]
        .as_array()
        .expect("notes array")
        .iter()
        .map(|note| note["id"].as_i64().unwrap())
        .collect()
}

#[tokio::test]
async fn empty_list() {
    let app = TestApp::new();
    let res = app.get("/notes").await;
    assert_eq!(res.status, StatusCode::OK);
    assert_eq!(res.json(), json!({"notes": []}));
}

#[tokio::test]
async fn lists_full_notes() {
    let app = seeded().await;
    let res = app.get("/notes?tag=misc").await;
    assert_eq!(
        res.json(),
        json!({"notes": [{"id": 2, "title": "other", "body": "say HELLO", "tags": ["greet", "misc"]}]})
    );
}

#[tokio::test]
async fn filters() {
    let app = seeded().await;
    assert_eq!(list_ids(&app, "/notes").await, [1, 2, 3]);
    assert_eq!(list_ids(&app, "/notes?tag=greet").await, [1, 2]);
    assert_eq!(list_ids(&app, "/notes?tag=Greet").await, [] as [i64; 0]);
    assert_eq!(list_ids(&app, "/notes?q=hello").await, [1, 2]);
    assert_eq!(list_ids(&app, "/notes?q=hello%20WORLD").await, [1]);
    assert_eq!(list_ids(&app, "/notes?q=hello+world").await, [1]);
    assert_eq!(list_ids(&app, "/notes?q=hello&tag=misc").await, [2]);
    assert_eq!(list_ids(&app, "/notes?q=").await, [1, 2, 3]);
    assert_eq!(list_ids(&app, "/notes?after=1&q=o&limit=1").await, [2]);
    assert_eq!(list_ids(&app, "/notes?unknown=1").await, [1, 2, 3]);
}

#[tokio::test]
async fn paging() {
    let app = seeded().await;
    assert_eq!(list_ids(&app, "/notes?limit=2").await, [1, 2]);
    assert_eq!(list_ids(&app, "/notes?after=2&limit=2").await, [3]);
    assert_eq!(list_ids(&app, "/notes?after=0").await, [1, 2, 3]);
    assert_eq!(list_ids(&app, "/notes?after=-10").await, [1, 2, 3]);
    assert_eq!(list_ids(&app, "/notes?after=3").await, [] as [i64; 0]);
    assert_eq!(list_ids(&app, "/notes?limit=100").await, [1, 2, 3]);
}

#[tokio::test]
async fn default_limit_is_100() {
    let app = TestApp::new();
    for i in 0..105 {
        let res = app.post("/notes", &format!(r#"{{"title":"n{i}"}}"#)).await;
        assert_eq!(res.status, StatusCode::CREATED);
    }
    let ids = list_ids(&app, "/notes").await;
    assert_eq!(ids, (1..=100).collect::<Vec<_>>());
    assert_eq!(
        list_ids(&app, "/notes?after=100").await,
        [101, 102, 103, 104, 105]
    );
}

#[tokio::test]
async fn invalid_parameters() {
    let app = seeded().await;
    for uri in [
        "/notes?limit=0",
        "/notes?limit=101",
        "/notes?limit=-1",
        "/notes?limit=",
        "/notes?limit=abc",
        "/notes?limit=2.5",
        "/notes?after=",
        "/notes?after=abc",
        "/notes?after=1.5",
        "/notes?after=99999999999999999999",
    ] {
        let res = app.get(uri).await;
        assert_eq!(res.status, StatusCode::BAD_REQUEST, "{uri}");
        assert!(matches!(res.json()["error"], Value::String(_)), "{uri}");
    }
}

#[tokio::test]
async fn other_methods_not_allowed() {
    let app = TestApp::new();
    for method in [Method::DELETE, Method::PUT, Method::PATCH] {
        let res = app.request(method.clone(), "/notes", None).await;
        assert_eq!(res.status, StatusCode::METHOD_NOT_ALLOWED, "{method}");
    }
}
