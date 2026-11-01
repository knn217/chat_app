use super::error::DbError;
use openssl::ssl::{SslConnector, SslFiletype, SslMethod, SslVerifyMode};
use postgres_openssl::MakeTlsConnector;
use std::collections::HashMap;
use url::Url;

/// Parses the database URL, extracts SSL file paths and mode, configures OpenSSL natively,
/// and returns both the cleaned tokio-postgres Config and the TLS connector.
pub(super) fn connector_from_url(
    database_url: &str,
) -> Result<(tokio_postgres::Config, MakeTlsConnector), DbError> {
    let parsed_url = Url::parse(database_url)
        .map_err(|e| DbError::Config(format!("Invalid connection URL: {}", e)))?;

    let query_params: HashMap<String, String> = parsed_url.query_pairs().into_owned().collect();

    // 1. Rebuild clean URL without query parameters for tokio-postgres
    let clean_url = format!(
        "postgresql://{}@{}:{}{}",
        parsed_url.username(),
        parsed_url.host_str().unwrap_or("localhost"),
        parsed_url.port().unwrap_or(26257),
        parsed_url.path()
    );

    let config: tokio_postgres::Config = clean_url
        .parse()
        .map_err(|e| DbError::Config(format!("Failed to parse database config: {}", e)))?;

    // 2. Initialize OpenSSL connector builder
    let mut builder =
        SslConnector::builder(SslMethod::tls()).map_err(|e| DbError::Connection(e.to_string()))?;

    // 3. Handle verification mode if specified
    if let Some(sslmode) = query_params.get("sslmode") {
        match sslmode.as_str() {
            "verify-full" | "verify-ca" => {
                builder.set_verify(SslVerifyMode::PEER);
            }
            _ => {}
        }
    }

    // 4. Pass file paths directly to OpenSSL's native file loaders
    if let Some(ca_path) = query_params.get("sslrootcert") {
        builder
            .set_ca_file(ca_path)
            .map_err(|e| DbError::Config(format!("Failed to load sslrootcert: {}", e)))?;
    }

    if let Some(cert_path) = query_params.get("sslcert") {
        builder
            .set_certificate_file(cert_path, SslFiletype::PEM)
            .map_err(|e| DbError::Config(format!("Failed to load sslcert: {}", e)))?;
    }

    if let Some(key_path) = query_params.get("sslkey") {
        builder
            .set_private_key_file(key_path, SslFiletype::PEM)
            .map_err(|e| DbError::Config(format!("Failed to load sslkey: {}", e)))?;
    }

    let connector = MakeTlsConnector::new(builder.build());
    Ok((config, connector))
}
