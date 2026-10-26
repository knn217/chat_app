use super::error::DbError;
use openssl::ssl::{SslConnector, SslMethod};
use postgres_openssl::MakeTlsConnector;

pub(super) fn connector() -> Result<MakeTlsConnector, DbError> {
    let builder =
        SslConnector::builder(SslMethod::tls()).map_err(|e| DbError::Connection(e.to_string()))?;
    Ok(MakeTlsConnector::new(builder.build()))
}
