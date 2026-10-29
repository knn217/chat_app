use std::sync::Arc;

use axum::Router;
use utoipa::{OpenApi, openapi};
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::auth;
use crate::db::Database;

// const CUSTOMER_TAG: &str = "customer";
// const ORDER_TAG: &str = "order";

#[derive(OpenApi)]
#[openapi(
    tags(
        // (name = CUSTOMER_TAG, description = "Customer API endpoints"),
        // (name = ORDER_TAG, description = "Order API endpoints")
    )
)]
struct ApiDoc;

async fn router() -> std::io::Result<OpenApiRouter> {
    // Connect once, here, inside the runtime.
    let db = Database::connect_from_env()
        .await
        .expect("failed to connect to database");
    db.create_users_table()
        .await
        .expect("failed to create users table");

    Ok(OpenApiRouter::new()
        .nest("/me", OpenApiRouter::new().routes(routes!(auth::me)))
        .nest(
            "/register",
            OpenApiRouter::new().routes(routes!(auth::register)),
        )
        .with_state(Arc::new(db)))
}

pub async fn create_router_api() -> std::io::Result<(Router, openapi::OpenApi)> {
    let router = router().await?;
    Ok(OpenApiRouter::with_openapi(ApiDoc::openapi())
        .nest("/api/v1/auth", router)
        .split_for_parts())
}
