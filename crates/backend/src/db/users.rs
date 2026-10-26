//! Queries for the `users` auth table.
//!
//! Normalization (`trim` + lowercase) happens here, so callers only ever deal with the
//! display form and can't mismatch the `*_normalized` columns. Password hashing is the
//! caller's job: this module stores and returns the hash it is given.

use super::{Database, error::DbError};
use postgres::{Row, error::SqlState, types::ToSql};
use std::{fmt, time::SystemTime};
use uuid::Uuid;

const COLS: &str = "user_id, username, email, password_hash, created_at, updated_at";

/// A row of the `users` table (display forms only).
#[derive(Clone)]
pub struct User {
    pub user_id: Uuid,
    pub username: String,
    pub email: String,
    pub password_hash: String,
    pub created_at: SystemTime,
    pub updated_at: SystemTime,
}

/// Input for [`Database::insert_user`]. `password_hash` must already be hashed.
#[derive(Clone)]
pub struct NewUser {
    pub username: String,
    pub email: String,
    pub password_hash: String,
}

// Manual Debug impls keep the hash out of logs.
impl fmt::Debug for User {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("User")
            .field("user_id", &self.user_id)
            .field("username", &self.username)
            .field("email", &self.email)
            .field("password_hash", &"<redacted>")
            .field("created_at", &self.created_at)
            .field("updated_at", &self.updated_at)
            .finish()
    }
}

impl fmt::Debug for NewUser {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("NewUser")
            .field("username", &self.username)
            .field("email", &self.email)
            .field("password_hash", &"<redacted>")
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
        password_hash: row.try_get(3).map_err(DbError::from_pg)?,
        created_at: row.try_get(4).map_err(DbError::from_pg)?,
        updated_at: row.try_get(5).map_err(DbError::from_pg)?,
    })
}

/// Maps unique-constraint violations on insert to `UsernameTaken` / `EmailTaken`.
fn map_insert_err(e: postgres::Error) -> DbError {
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

impl Database {
    pub fn create_users_table(&mut self) -> Result<(), DbError> {
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
            .map_err(DbError::from_pg)
    }

    /// Inserts a user and returns the stored row.
    /// Fails with `UsernameTaken` / `EmailTaken` on duplicates (compared normalized).
    pub fn insert_user(&mut self, new: &NewUser) -> Result<User, DbError> {
        let username_normalized = normalize(&new.username);
        let email_normalized = normalize(&new.email);
        if username_normalized.is_empty() {
            return Err(DbError::InvalidInput("username is empty".into()));
        }
        if email_normalized.is_empty() {
            return Err(DbError::InvalidInput("email is empty".into()));
        }
        if new.password_hash.is_empty() {
            return Err(DbError::InvalidInput("password_hash is empty".into()));
        }

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
                    &new.password_hash,
                ],
            )
            .map_err(map_insert_err)?;
        from_row(&row)
    }

    pub fn get_user_by_id(&mut self, user_id: Uuid) -> Result<Option<User>, DbError> {
        self.find_user("user_id", &user_id)
    }

    /// Case-insensitive lookup (input is normalized).
    pub fn get_user_by_username(&mut self, username: &str) -> Result<Option<User>, DbError> {
        self.find_user("username_normalized", &normalize(username))
    }

    /// Case-insensitive lookup (input is normalized).
    pub fn get_user_by_email(&mut self, email: &str) -> Result<Option<User>, DbError> {
        self.find_user("email_normalized", &normalize(email))
    }

    fn find_user(
        &mut self,
        column: &'static str,
        value: &(dyn ToSql + Sync),
    ) -> Result<Option<User>, DbError> {
        let sql = format!("SELECT {COLS} FROM users WHERE {column} = $1");
        let row = self
            .client
            .query_opt(&sql, &[value])
            .map_err(DbError::from_pg)?;
        row.as_ref().map(from_row).transpose()
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
