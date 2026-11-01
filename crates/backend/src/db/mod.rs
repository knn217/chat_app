//! Database module. This is the only place that knows about Postgres / CockroachDB.
//!
//! Callers use [`Database`], the plain data types, and [`DbError`]. No `tokio_postgres`,
//! `openssl`, `argon2` or SQL types leak through the public API, so the driver can be
//! swapped without touching any caller.
//!
//! Everything that touches the database is `async` and must be awaited inside a tokio
//! runtime (actix-web's runtime is one). `Database` methods take `&self`, so one instance
//! can be shared between handlers and background tasks (`web::Data<Database>` / `Arc`).

mod error;
mod password;
mod tls;
mod users;

pub use error::DbError;
pub use users::{NewUser, User};
/// Re-exported so callers don't need their own `uuid` dependency.
pub use uuid::Uuid;

use std::env;
use tokio_postgres::Client;

pub struct Database {
    client: Client,
}

impl Database {
    /// Connects using the `DATABASE_URL` environment variable.
    pub async fn connect_from_env() -> Result<Self, DbError> {
        let url = env::var("DATABASE_URL")
            .map_err(|_| DbError::Config("DATABASE_URL is not set".into()))?;
        Self::connect(&url).await
    }

    /// Connects using an explicit connection URL.
    pub async fn connect(url: &str) -> Result<Self, DbError> {
        println!("url: {}", url);

        // This returns the parsed Config (with file paths stripped) and the configured OpenSSL connector
        let (config, tls) = tls::connector_from_url(url)?;

        // Call .connect() directly on the config object
        let (client, connection) = config
            .connect(tls)
            .await
            .map_err(|e| DbError::Connection(e.to_string()))?;

        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("database connection error: {e}");
            }
        });

        Ok(Self { client })
    }
}
