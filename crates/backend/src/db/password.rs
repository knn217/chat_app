//! Internal password hashing (Argon2id, PHC string format). Never exposed to callers.
//!
//! Argon2 is deliberately CPU-heavy, so the async entry points run it on tokio's blocking
//! pool instead of stalling the async worker threads.

use super::error::DbError;
use argon2::{
    Argon2,
    password_hash::{
        Error as HashError, PasswordHash, PasswordHasher, PasswordVerifier, SaltString,
        rand_core::OsRng,
    },
};
use std::sync::OnceLock;

fn hash_blocking(password: &str) -> Result<String, DbError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| DbError::Hash(e.to_string()))
}

fn verify_blocking(password: &str, stored_hash: &str) -> Result<bool, DbError> {
    let parsed = PasswordHash::new(stored_hash).map_err(|e| DbError::Hash(e.to_string()))?;
    match Argon2::default().verify_password(password.as_bytes(), &parsed) {
        Ok(()) => Ok(true),
        Err(HashError::Password) => Ok(false),
        Err(e) => Err(DbError::Hash(e.to_string())),
    }
}

fn burn_blocking(password: &str) {
    static DUMMY_HASH: OnceLock<String> = OnceLock::new();
    let dummy = DUMMY_HASH.get_or_init(|| hash_blocking("dummy-password").unwrap_or_default());
    let _ = verify_blocking(password, dummy);
}

/// Hashes `password` with a fresh random salt. The result embeds salt and parameters.
pub(super) async fn hash_password(password: &str) -> Result<String, DbError> {
    let password = password.to_owned();
    tokio::task::spawn_blocking(move || hash_blocking(&password))
        .await
        .map_err(|e| DbError::Hash(e.to_string()))?
}

/// `Ok(true)` on match, `Ok(false)` on mismatch, `Err` if the stored hash is malformed.
pub(super) async fn verify_password(password: &str, stored_hash: String) -> Result<bool, DbError> {
    let password = password.to_owned();
    tokio::task::spawn_blocking(move || verify_blocking(&password, &stored_hash))
        .await
        .map_err(|e| DbError::Hash(e.to_string()))?
}

/// Spends roughly the same time as a real verification. Used when the user doesn't exist,
/// so response time doesn't reveal which usernames/emails are registered.
pub(super) async fn burn_verify(password: &str) {
    let password = password.to_owned();
    let _ = tokio::task::spawn_blocking(move || burn_blocking(&password)).await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_then_verify_round_trip() {
        let hash = hash_blocking("correct horse").expect("hashing should succeed");
        assert_ne!(hash, "correct horse");
        assert!(verify_blocking("correct horse", &hash).expect("verify should succeed"));
        assert!(!verify_blocking("wrong", &hash).expect("verify should succeed"));
    }

    #[test]
    fn hashes_are_salted() {
        let a = hash_blocking("same").expect("hashing should succeed");
        let b = hash_blocking("same").expect("hashing should succeed");
        assert_ne!(a, b);
    }
}
