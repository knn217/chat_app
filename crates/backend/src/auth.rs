// Dep
use actix_web::{Error, HttpResponse, error, get, post, web};
use actix_web_validator::Json;
use utoipa;

// Local
use crate::db::{Database, DbError, NewUser};

#[utoipa::path(
    responses(
        (status = 200, description = "Success", body = NewUser)
    )
)]
#[get("/me")]
async fn me() -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body("Hello world!"))
}
#[utoipa::path(
    responses(
        (status = 200, description = "Success")
    )
)]
#[post("/register")]
async fn register(db: web::Data<Database>, req_body: Json<NewUser>) -> Result<HttpResponse, Error> {
    // Insert to db
    let _user = db.insert_user(&req_body).await.map_err(|e| match e {
        DbError::UsernameTaken => {
            error::ErrorConflict(format!("Database insertion failed: {:?}", e))
        }
        _ => error::ErrorInternalServerError(format!("Database insertion failed: {:?}", e)),
    })?;
    // Response
    Ok(HttpResponse::Created().finish())
}
#[utoipa::path(
    responses(
        (status = 200, description = "Success", body = String)
    )
)]
#[post("/login")]
async fn login(req_body: String) -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body(req_body))
}
#[utoipa::path(
    responses(
        (status = 200, description = "Success", body = String)
    )
)]
#[post("/refresh")]
async fn refresh(req_body: String) -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body(req_body))
}
#[utoipa::path(
    responses(
        (status = 200, description = "Success", body = String)
    )
)]
#[post("/logout")]
async fn logout(req_body: String) -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body(req_body))
}
