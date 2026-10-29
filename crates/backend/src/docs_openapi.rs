pub mod auth;
pub mod db;
pub mod server;

#[tokio::main]
async fn main() -> std::io::Result<()> {
    let (_router, api) = server::create_router_api().await?;

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
