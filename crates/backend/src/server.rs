// Dep
use actix_web::{HttpRequest, HttpResponse};
use utoipa_actix_web::scope;
use utoipa_actix_web::service_config::ServiceConfig;

// Local
use crate::auth;

pub async fn default_handler(req: HttpRequest) -> HttpResponse {
    if req.resource_map().has_resource(req.path()) {
        HttpResponse::MethodNotAllowed().finish()
    } else {
        HttpResponse::NotFound().finish()
    }
}

pub fn config_server(cfg: &mut ServiceConfig) {
    cfg.service(
        scope::scope("/api/v1/auth")
            .service(auth::me)
            .service(auth::register)
            .service(auth::login)
            .service(auth::refresh)
            .service(auth::logout),
    );
}
