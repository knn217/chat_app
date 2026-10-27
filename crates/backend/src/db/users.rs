//! Queries for the `users` auth table.
//!
//! Normalization (`trim` + lowercase) and password hashing both happen inside this module.
//! Callers only ever pass the plaintext `password` and never see a hash.
//! All methods are `async` and take `&self`.

// std
use std::{fmt, time::SystemTime};

// dep
use serde::Deserialize;
use tokio_postgres::{Row, error::SqlState, types::ToSql};
use utoipa::ToSchema;
use uuid::Uuid;
use validator::{Validate, ValidationError};

// local
use super::{
    Database,
    error::DbError,
    password::{burn_verify, hash_password, verify_password},
};

const COLS: &str = "user_id, username, email, created_at, updated_at";

/// A row of the `users` table (display forms only; no password data).
#[derive(Debug, Clone)]
pub struct User {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub created_at: SystemTime,
    pub updated_at: SystemTime,
}

fn validate_password(password: &str) -> Result<(), ValidationError> {
    if password.len() < 8 {
        let mut err = ValidationError::new("length");
        err.message = Some("Password must be at least 8 characters long".into());
        return Err(err);
    }

    let has_lowercase = password.chars().any(|c| c.is_lowercase());
    let has_uppercase = password.chars().any(|c| c.is_uppercase());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    let has_special = password.chars().any(|c| "@$!%*?&".contains(c));

    if !has_lowercase || !has_uppercase || !has_digit || !has_special {
        let mut err = ValidationError::new("complexity");
        err.message = Some("Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character".into());
        return Err(err);
    }

    Ok(())
}

/// Input for [`Database::insert_user`]. `password` is plaintext and is hashed internally.
#[derive(Deserialize, Validate, ToSchema)]
pub struct NewUser {
    #[schema(example = "John Smith")]
    #[validate(length(min = 3, max = 50))]
    pub username: String,
    #[schema(example = "johnsmith@gmail.com")]
    #[validate(email)]
    pub email: String,
    #[schema(example = "John@Smith123")]
    #[validate(custom(function = "validate_password"))]
    pub password: String,
}

// Manual Debug impl keeps the password out of logs.
impl fmt::Debug for NewUser {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NewUser")
            .field("username", &self.username)
            .field("email", &self.email)
            .field("password", &"<redacted>")
            .finish()
    }
}

fn normalize(s: &str) -> String {
    s.trim().to_lowercase()
}

fn from_row(row: &Row) -> Result<User, DbError> {
    Ok(User {
        user_id: row.try_get(0).map_err(DbError::from_pg)?,
        username: row.try_get(1).map_err(DbError::from_pg)?,
        email: row.try_get(2).map_err(DbError::from_pg)?,
        created_at: row.try_get(3).map_err(DbError::from_pg)?,
        updated_at: row.try_get(4).map_err(DbError::from_pg)?,
    })
}

/// Maps unique-constraint violations on insert to `UsernameTaken` / `EmailTaken`.
fn map_insert_err(e: tokio_postgres::Error) -> DbError {
    if e.code() == Some(&SqlState::UNIQUE_VIOLATION) {
        let db_err = e.as_db_error();
        let constraint = db_err.and_then(|d| d.constraint()).unwrap_or("");
        let message = db_err.map(|d| d.message()).unwrap_or("");
        let hit = |name: &str| constraint == name || message.contains(name);
        if hit("users_username_normalized_key") {
            return DbError::UsernameTaken;
        }
        if hit("users_email_normalized_key") {
            return DbError::EmailTaken;
        }
    }
    DbError::from_pg(e)
}

/// Verifies `password` against a found user. Unknown user and wrong password both give
/// `None`, and an unknown user still pays the hashing cost.
async fn check_password(
    found: Option<(User, String)>,
    password: &str,
) -> Result<Option<User>, DbError> {
    match found {
        Some((user, hash)) => Ok(verify_password(password, hash).await?.then_some(user)),
        None => {
            burn_verify(password).await;
            Ok(None)
        }
    }
}

impl Database {
    pub async fn create_users_table(&self) -> Result<(), DbError> {
        self.client
            .batch_execute(
                "CREATE TABLE IF NOT EXISTS users (
                    user_id             UUID        NOT NULL DEFAULT gen_random_uuid(),
                    username            STRING      NOT NULL,
                    username_normalized STRING      NOT NULL,
                    email               STRING      NOT NULL,
                    email_normalized    STRING      NOT NULL,
                    password_hash       STRING      NOT NULL,
                    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
                    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now() ON UPDATE now(),

                    CONSTRAINT users_pkey PRIMARY KEY (user_id),
                    CONSTRAINT users_username_normalized_key UNIQUE (username_normalized),
                    CONSTRAINT users_email_normalized_key UNIQUE (email_normalized),
                    CONSTRAINT users_username_normalized_nonempty CHECK (username_normalized <> ''),
                    CONSTRAINT users_email_normalized_nonempty CHECK (email_normalized <> ''),
                    CONSTRAINT users_password_hash_nonempty CHECK (password_hash <> '')
                )",
            )
            .await
            .map_err(DbError::from_pg)
    }

    /// Hashes the password, inserts the user and returns the stored row.
    /// Fails with `UsernameTaken` / `EmailTaken` on duplicates (compared normalized).
    pub async fn insert_user(&self, new: &NewUser) -> Result<User, DbError> {
        let username_normalized = normalize(&new.username);
        let email_normalized = normalize(&new.email);
        if username_normalized.is_empty() {
            return Err(DbError::InvalidInput("username is empty".into()));
        }
        if email_normalized.is_empty() {
            return Err(DbError::InvalidInput("email is empty".into()));
        }
        if new.password.is_empty() {
            return Err(DbError::InvalidInput("password is empty".into()));
        }
        let password_hash = hash_password(&new.password).await?;

        let sql = format!(
            "INSERT INTO users (username, username_normalized, email, email_normalized, password_hash)
             VALUES ($1, $2, $3, $4, $5)
             RETURNING {COLS}"
        );
        let row = self
            .client
            .query_one(
                &sql,
                &[
                    &new.username,
                    &username_normalized,
                    &new.email,
                    &email_normalized,
                    &password_hash,
                ],
            )
            .await
            .map_err(map_insert_err)?;
        from_row(&row)
    }

    /// Returns the user if the username and password match, otherwise `None`
    /// (unknown user and wrong password are deliberately indistinguishable).
    pub async fn authenticate_by_username(
        &self,
        username: &str,
        password: &str,
    ) -> Result<Option<User>, DbError> {
        let found = self
            .find("username_normalized", &normalize(username))
            .await?;
        check_password(found, password).await
    }

    /// Same as [`Database::authenticate_by_username`], but identifies the user by email.
    pub async fn authenticate_by_email(
        &self,
        email: &str,
        password: &str,
    ) -> Result<Option<User>, DbError> {
        let found = self.find("email_normalized", &normalize(email)).await?;
        check_password(found, password).await
    }

    pub async fn get_user_by_id(&self, user_id: Uuid) -> Result<Option<User>, DbError> {
        Ok(self.find("user_id", &user_id).await?.map(|(user, _)| user))
    }

    /// Case-insensitive lookup (input is normalized).
    pub async fn get_user_by_username(&self, username: &str) -> Result<Option<User>, DbError> {
        Ok(self
            .find("username_normalized", &normalize(username))
            .await?
            .map(|(user, _)| user))
    }

    /// Case-insensitive lookup (input is normalized).
    pub async fn get_user_by_email(&self, email: &str) -> Result<Option<User>, DbError> {
        Ok(self
            .find("email_normalized", &normalize(email))
            .await?
            .map(|(user, _)| user))
    }

    /// Internal lookup returning the user together with its stored hash.
    async fn find(
        &self,
        column: &'static str,
        value: &(dyn ToSql + Sync),
    ) -> Result<Option<(User, String)>, DbError> {
        let sql = format!("SELECT {COLS}, password_hash FROM users WHERE {column} = $1");
        let row = self
            .client
            .query_opt(&sql, &[value])
            .await
            .map_err(DbError::from_pg)?;
        match row {
            Some(row) => {
                let hash: String = row.try_get(5).map_err(DbError::from_pg)?;
                Ok(Some((from_row(&row)?, hash)))
            }
            None => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_trims_and_lowercases() {
        assert_eq!(normalize("  Bob@Example.COM "), "bob@example.com");
        assert_eq!(normalize("   "), "");
    }
}
