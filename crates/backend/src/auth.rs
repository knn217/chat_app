// Dep
use actix_web::{Error, HttpResponse, error::ErrorInternalServerError, get, post, web};

// Local
use crate::db::{Database, NewUser};

#[get("/me")]
async fn me() -> Result<HttpResponse, Error> {
    Ok(HttpResponse::Ok().body("Hello world!"))
}
#[post("/register")]
async fn register(mut req_body: web::Json<NewUser>) -> Result<HttpResponse, Error> {
    // Connect to db
    let mut db = Database::connect_from_env()
        .map_err(|e| ErrorInternalServerError(format!("Database connection failed: {:?}", e)))?;
    // Hash the password
    req_body.password_hash = "abc".into();
    // Insert to db
    let _user = db
        .insert_user(&req_body)
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
