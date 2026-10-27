// Dep
use actix_web::{App, HttpServer, middleware::Logger, web};
use env_logger::Env;

// Local
pub mod auth;
pub mod db;
use db::Database;

// Main function use actix web's async runtime
#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(Env::default().default_filter_or("info"));

    // Connect once, here, inside the runtime.
    let db = Database::connect_from_env()
        .await
        .expect("failed to connect to database");
    db.create_users_table()
        .await
        .expect("failed to create users table");
    let db = web::Data::new(db);

    HttpServer::new(move || {
        App::new()
            .wrap(Logger::default())
            .wrap(Logger::new("%a %{User-Agent}i"))
            .app_data(db.clone()) // cheap Arc clone per worker
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
