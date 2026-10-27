//! Database module. This is the only place that knows about Postgres / CockroachDB.
//!
//! Callers use [`Database`], the plain data types, and [`DbError`]. No `postgres`,
//! `openssl` or SQL types leak through the public API, so the driver can be swapped
//! (e.g. to `tokio-postgres`) without touching any caller.

mod error;
mod password;
mod tls;
mod txn;
mod users;

pub use error::DbError;
pub use users::{NewUser, User};
/// Re-exported so callers don't need their own `uuid` dependency.
pub use uuid::Uuid;

use postgres::Client;
use std::env;

pub struct Database {
    client: Client,
}

impl Database {
    /// Connects using the `DATABASE_URL` environment variable.
    pub fn connect_from_env() -> Result<Self, DbError> {
        let url = env::var("DATABASE_URL")
            .map_err(|_| DbError::Config("DATABASE_URL is not set".into()))?;
        Self::connect(&url)
    }

    /// Connects using an explicit connection URL.
    pub fn connect(url: &str) -> Result<Self, DbError> {
        let tls = tls::connector()?;
        let client = Client::connect(url, tls).map_err(|e| DbError::Connection(e.to_string()))?;
        Ok(Self { client })
    }
}
