use std::sync::Arc;

use axum::{Json, extract::State, http::StatusCode};

// Local
use crate::db::{Database, DbError, NewUser};

#[utoipa::path(get, path = "", responses((status = OK, body = String)))]
pub async fn me() -> Result<(StatusCode, String), StatusCode> {
    Ok((StatusCode::OK, "Hello world!".into()))
}

#[utoipa::path(
    post,
    path = "",
    responses(
        (status = 201, description = "User registered successfully"),
        (status = 400, description = "Bad request (invalid JSON or payload syntax)"),
        (status = 409, description = "Username already taken"),
        (status = 500, description = "Internal server error"),
    )
)]
pub async fn register(
    State(db): State<Arc<Database>>,
    req_body: Json<NewUser>,
) -> Result<(StatusCode, ()), StatusCode> {
    // Insert to db
    let _user = db.insert_user(&req_body).await.map_err(|e| match e {
        DbError::UsernameTaken => StatusCode::CONFLICT,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    })?;
    // Response
    Ok((StatusCode::CREATED, ()))
}
