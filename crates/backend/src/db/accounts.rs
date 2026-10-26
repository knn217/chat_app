//! Account queries. Swap or extend this file (e.g. `users.rs`) with your own tables;
//! each file adds an `impl Database` block and plain return types.

use super::{Database, error::DbError, txn::execute_txn};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Account {
    pub id: Uuid,
    pub balance: i64,
}

impl Database {
    pub fn create_accounts_table(&mut self) -> Result<(), DbError> {
        self.client
            .execute(
                "CREATE TABLE IF NOT EXISTS accounts (id UUID PRIMARY KEY, balance INT8)",
                &[],
            )
            .map_err(DbError::from_pg)?;
        Ok(())
    }

    /// Deletes all accounts; returns the number of rows removed.
    pub fn delete_accounts(&mut self) -> Result<u64, DbError> {
        self.client
            .execute("DELETE FROM accounts", &[])
            .map_err(DbError::from_pg)
    }

    /// Inserts an account with a server-generated id and returns that id.
    pub fn insert_account(&mut self, balance: i64) -> Result<Uuid, DbError> {
        let row = self
            .client
            .query_one(
                "INSERT INTO accounts (id, balance) VALUES (gen_random_uuid(), $1) RETURNING id",
                &[&balance],
            )
            .map_err(DbError::from_pg)?;
        row.try_get(0).map_err(DbError::from_pg)
    }

    pub fn list_accounts(&mut self) -> Result<Vec<Account>, DbError> {
        let rows = self
            .client
            .query("SELECT id, balance FROM accounts", &[])
            .map_err(DbError::from_pg)?;
        rows.iter()
            .map(|row| {
                Ok(Account {
                    id: row.try_get(0).map_err(DbError::from_pg)?,
                    balance: row.try_get(1).map_err(DbError::from_pg)?,
                })
            })
            .collect()
    }

    /// Moves `amount` from one account to another atomically (with retries).
    pub fn transfer_funds(&mut self, from: Uuid, to: Uuid, amount: i64) -> Result<(), DbError> {
        execute_txn(&mut self.client, |txn| {
            let available: i64 = txn
                .query_one("SELECT balance FROM accounts WHERE id = $1", &[&from])?
                .try_get(0)?;
            if available < amount {
                return Err(DbError::InsufficientFunds {
                    available,
                    requested: amount,
                }
                .into());
            }
            txn.execute(
                "UPDATE accounts SET balance = balance - $1 WHERE id = $2",
                &[&amount, &from],
            )?;
            txn.execute(
                "UPDATE accounts SET balance = balance + $1 WHERE id = $2",
                &[&amount, &to],
            )?;
            Ok(())
        })
    }
}
