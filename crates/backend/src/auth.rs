use std::sync::Arc;

use axum::{extract::Json, extract::State, extract::rejection::JsonRejection, http::StatusCode};
use validator::Validate;

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
    payload: Result<Json<NewUser>, JsonRejection>, // Capture Axum's JsonRejection instead of letting it auto-fail
) -> Result<(StatusCode, ()), (StatusCode, String)> {
    // Validate request body
    let Json(new_user) = payload.map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;
    new_user.validate().map_err(|e| {
        (
            StatusCode::BAD_REQUEST,
            format!("Invalid request body error: {}", e),
        )
    })?;

    // Insert to db
    let _user = db.insert_user(&new_user).await.map_err(|e| match e {
        DbError::UsernameTaken | DbError::EmailTaken => {
            (StatusCode::CONFLICT, format!("Failed DB insertion: {}", e))
        }
        _ => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed DB insertion: {}", e),
        ),
    })?;
    // Response
    Ok((StatusCode::CREATED, ()))
}
