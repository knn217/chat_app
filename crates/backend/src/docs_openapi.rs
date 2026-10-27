// Dep
use utoipa::OpenApi;

// Import your ApiDoc definition from your main crate
// use my_backend_app::ApiDoc;

#[allow(dead_code)]
#[derive(OpenApi)]
#[openapi(
    info(title = "Auth & User API", version = "1.0")
    // paths(...), schemas(...)
)]
struct ApiDoc;

// Pull in everything from main.rs right here
include!("./main.rs");
