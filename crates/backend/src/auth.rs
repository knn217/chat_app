// Dep
use actix_web::{Error, HttpResponse, error::ErrorInternalServerError, get, post};
use actix_web_validator::Json;

// Local
use crate::db::{Database, NewUser};

#[get("/me")]
async fn me() -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body("Hello world!"))
}
#[post("/register")]
async fn register(req_body: Json<NewUser>) -> Result<HttpResponse, Error> {
    // Connect to db
    let db = Database::connect_from_env()
        .await
        .map_err(|e| ErrorInternalServerError(format!("Database connection failed: {:?}", e)))?;
    // Insert to db
    let _user = db
        .insert_user(&req_body)
        .await
        .map_err(|e| ErrorInternalServerError(format!("Database insertion failed: {:?}", e)))?;
    // Response
    Ok(HttpResponse::Created().finish())
}
#[post("/login")]
async fn login(req_body: String) -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body(req_body))
}
#[post("/refresh")]
async fn refresh(req_body: String) -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body(req_body))
}
#[post("/logout")]
async fn logout(req_body: String) -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body(req_body))
}
