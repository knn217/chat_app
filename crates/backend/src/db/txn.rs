#![allow(dead_code)] // kept for upcoming multi-statement queries; unused for now

use super::error::DbError;
use postgres::{Client, Transaction, error::SqlState};

/// Internal error type for transaction closures. Never exposed outside `db`.
pub(super) enum TxnError {
    /// Driver error; may be a retryable serialization failure.
    Pg(postgres::Error),
    /// Domain error; aborts the transaction without retry.
    Abort(DbError),
}

impl From<postgres::Error> for TxnError {
    fn from(e: postgres::Error) -> Self {
        TxnError::Pg(e)
    }
}

impl From<DbError> for TxnError {
    fn from(e: DbError) -> Self {
        TxnError::Abort(e)
    }
}

impl TxnError {
    fn is_retryable(&self) -> bool {
        matches!(
            self,
            TxnError::Pg(e) if e.code() == Some(&SqlState::T_R_SERIALIZATION_FAILURE)
        )
    }

    fn into_db_error(self) -> DbError {
        match self {
            TxnError::Pg(e) => DbError::from_pg(e),
            TxnError::Abort(e) => e,
        }
    }
}

/// Runs `op` inside a transaction and retries it on CockroachDB serialization
/// failures. On other errors the transaction is rolled back; on success it is committed.
/// See https://www.cockroachlabs.com/docs/stable/advanced-client-side-transaction-retries
pub(super) fn execute_txn<T, F>(client: &mut Client, op: F) -> Result<T, DbError>
where
    F: Fn(&mut Transaction) -> Result<T, TxnError>,
{
    run(client, op).map_err(TxnError::into_db_error)
}

fn run<T, F>(client: &mut Client, op: F) -> Result<T, TxnError>
where
    F: Fn(&mut Transaction) -> Result<T, TxnError>,
{
    let mut txn = client.transaction()?;
    let value = loop {
        let mut sp = txn.savepoint("cockroach_restart")?;
        let result = op(&mut sp).and_then(|t| sp.commit().map(|_| t).map_err(TxnError::from));
        match result {
            Err(ref e) if e.is_retryable() => {}
            r => break r?,
        }
    };
    txn.commit()?;
    Ok(value)
}
