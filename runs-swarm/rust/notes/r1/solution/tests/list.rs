//! `GET /notes` and its query parameters.

mod common;

use axum::http::{Method, StatusCode};
use serde_json::{Value, json};

use common::{TestApp, assert_bad_request};

async fn seed(app: &TestApp) {
    for body in [
        r#"{"title":"Hello world","tags":["greet"]}"#,
        r#"{"title":"other","body":"say HELLO","tags":["misc","greet"]}"#,
        r#"{"title":"nothing"}"#,
    ] {
        assert_eq!(app.post("/notes", body).await.status, StatusCode::CREATED);
    }
}

async fn ids(app: &TestApp, uri: &str) -> Vec<i64> {
    let response = app.get(uri).await;
    assert_eq!(
        response.status,
        StatusCode::OK,
        "{uri}: {}",
        response.text()
    );
    response.json()["notes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| n["id"].as_i64().unwrap())
        .collect()
}

#[tokio::test]
async fn empty_store_lists_nothing() {
    let app = TestApp::new();
    let response = app.get("/notes").await;
    assert_eq!(response.status, StatusCode::OK);
    assert_eq!(response.content_type.as_deref(), Some("application/json"));
    assert_eq!(response.json(), json!({"notes": []}));
}

#[tokio::test]
async fn lists_full_notes_in_id_order() {
    let app = TestApp::new();
    seed(&app).await;
    let notes: Value = app.get("/notes").await.json();
    assert_eq!(
        notes,
        json!({"notes": [
            {"id": 1, "title": "Hello world", "body": "", "tags": ["greet"]},
            {"id": 2, "title": "other", "body": "say HELLO", "tags": ["greet", "misc"]},
            {"id": 3, "title": "nothing", "body": "", "tags": []},
        ]})
    );
}

#[tokio::test]
async fn filters_by_tag_and_text() {
    let app = TestApp::new();
    seed(&app).await;
    assert_eq!(ids(&app, "/notes?tag=greet").await, [1, 2]);
    assert_eq!(ids(&app, "/notes?tag=misc").await, [2]);
    assert_eq!(ids(&app, "/notes?tag=unknown").await, Vec::<i64>::new());
    assert_eq!(ids(&app, "/notes?q=hello").await, [1, 2]);
    assert_eq!(ids(&app, "/notes?q=WORLD").await, [1]);
    assert_eq!(ids(&app, "/notes?q=say%20hello").await, [2]);
    assert_eq!(ids(&app, "/notes?q=say+hello").await, [2]);
    assert_eq!(ids(&app, "/notes?q=%25").await, Vec::<i64>::new());
    assert_eq!(ids(&app, "/notes?q=hello&tag=misc").await, [2]);
    assert_eq!(ids(&app, "/notes?q=hello&tag=greet&after=1").await, [2]);
}

#[tokio::test]
async fn pages_with_after_and_limit() {
    let app = TestApp::new();
    for i in 1..=105 {
        app.post("/notes", &format!(r#"{{"title":"n{i}"}}"#)).await;
    }
    assert_eq!(ids(&app, "/notes").await, (1..=100).collect::<Vec<_>>());
    assert_eq!(ids(&app, "/notes?limit=2").await, [1, 2]);
    assert_eq!(ids(&app, "/notes?after=2&limit=2").await, [3, 4]);
    assert_eq!(
        ids(&app, "/notes?after=100").await,
        [101, 102, 103, 104, 105]
    );
    assert_eq!(ids(&app, "/notes?after=0&limit=1").await, [1]);
    assert_eq!(ids(&app, "/notes?after=105").await, Vec::<i64>::new());
}

#[tokio::test]
async fn rejects_invalid_limit_and_after() {
    let app = TestApp::new();
    seed(&app).await;
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
    ] {
        assert_bad_request(&app.get(&format!("/notes?{query}")).await);
    }
}

#[tokio::test]
async fn other_methods_are_not_allowed() {
    let app = TestApp::new();
    let response = app.request(Method::DELETE, "/notes", None).await;
    assert_eq!(response.status, StatusCode::METHOD_NOT_ALLOWED);
}
