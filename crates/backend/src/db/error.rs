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
    /// Input failed validation before reaching the database (e.g. empty username).
    InvalidInput(String),
    /// Password hashing or verification failed (e.g. malformed stored hash).
    Hash(String),
    /// Username already registered (compared in normalized form).
    UsernameTaken,
    /// Email already registered (compared in normalized form).
    EmailTaken,
}

impl DbError {
    pub(super) fn from_pg(e: tokio_postgres::Error) -> Self {
        DbError::Query(e.to_string())
    }
}

impl fmt::Display for DbError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            DbError::Config(m) => write!(f, "database config error: {m}"),
            DbError::Connection(m) => write!(f, "database connection error: {m}"),
            DbError::Query(m) => write!(f, "database query error: {m}"),
            DbError::InvalidInput(m) => write!(f, "invalid input: {m}"),
            DbError::Hash(m) => write!(f, "password hashing error: {m}"),
            DbError::UsernameTaken => write!(f, "username is already taken"),
            DbError::EmailTaken => write!(f, "email is already registered"),
        }
    }
}

impl std::error::Error for DbError {}
