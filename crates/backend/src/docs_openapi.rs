// dep
use actix_web::App;
use env_logger::Env;
use utoipa_actix_web::AppExt;

// local
pub mod auth;
pub mod db;
pub mod server;

fn main() -> std::io::Result<()> {
    env_logger::init_from_env(Env::default().default_filter_or("info"));

    // 1. Build the App and split it to get the 'api' specification
    let (_app, api) = App::new()
        .into_utoipa_app()
        .configure(server::config_server)
        .split_for_parts();

    // 2. Write the JSON file directly to your local machine
    std::fs::write(
        "openapi.json",
        api.to_pretty_json().expect("Failed to export to json"),
    )
    .expect("Failed to write openapi.json");

    println!("Successfully exported openapi.json!");

    // 3. Exit immediately without starting the HttpServer loop!
    Ok(())
}
