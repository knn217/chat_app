// Dep
use actix_web::{App, HttpServer, middleware::Logger, web};
use env_logger::Env;

// Local
pub mod auth;
pub mod db;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(Env::default().default_filter_or("info"));

    HttpServer::new(|| {
        App::new()
            .wrap(Logger::default())
            .wrap(Logger::new("%a %{User-Agent}i"))
            .service(
                web::scope("/api/v1/auth")
                    .service(auth::me)
                    .service(auth::register)
                    .service(auth::login)
                    .service(auth::refresh)
                    .service(auth::logout),
            )
        // .service(auth::hello)
        // .service(auth::echo)
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
