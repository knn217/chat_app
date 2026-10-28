// Dep
use utoipa_actix_web::scope;
use utoipa_actix_web::service_config::ServiceConfig;

// Local
use crate::auth;

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
