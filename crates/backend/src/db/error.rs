use std::fmt;

/// The only error type callers of the `db` module ever see.
#[derive(Debug)]
pub enum DbError {
    /// Missing or invalid configuration (e.g. `DATABASE_URL` not set).
    Config(String),
    /// Could not establish a connection (network or TLS).
    Connection(String),
    /// A query or transaction failed.
    Query(String),
    /// A transfer was rejected because the source balance is too low.
    InsufficientFunds { available: i64, requested: i64 },
}

impl DbError {
    pub(super) fn from_pg(e: postgres::Error) -> Self {
        DbError::Query(e.to_string())
    }
}

impl fmt::Display for DbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DbError::Config(m) => write!(f, "database config error: {m}"),
            DbError::Connection(m) => write!(f, "database connection error: {m}"),
            DbError::Query(m) => write!(f, "database query error: {m}"),
            DbError::InsufficientFunds {
                available,
                requested,
            } => write!(
                f,
                "insufficient funds: available {available}, requested {requested}"
            ),
        }
    }
}

impl std::error::Error for DbError {}
