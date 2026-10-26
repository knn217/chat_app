# db module

Barebone query layer for CockroachDB (Postgres wire protocol). It is the only code
that knows about `postgres`, `openssl` or SQL. Callers use `Database`, plain data
types and `DbError`, so the driver can be swapped without touching any caller.

## Layout

| File | Purpose |
|------|---------|
| `mod.rs` | `Database` (owns the client), `connect_from_env()`, `connect(url)`; re-exports |
| `users.rs` | `users` auth table: `User`, `NewUser`, insert and lookups |
| `txn.rs` | Private `execute_txn`: transaction with automatic retry on serialization failures (unused until a query needs several statements) |
| `error.rs` | `DbError`, the only error type callers see |
| `tls.rs` | Private openssl TLS connector |

## Setup

Add to `Cargo.toml`:

```toml
postgres = { version = "0.19", features = ["with-uuid-1"] }
postgres-openssl = "0.5"
openssl = "0.10"
uuid = "1"
```

Copy the folder into your crate as `src/db/` and declare it:

```rust
mod db;
```

`Database::connect_from_env()` reads `DATABASE_URL`, for example:

```
postgresql://user:password@host:26257/dbname?sslmode=require
```

## Usage

```rust
mod db;
use db::{Database, DbError, NewUser};

fn main() -> Result<(), DbError> {
    let mut db = Database::connect_from_env()?;
    db.create_users_table()?;

    let user = db.insert_user(&NewUser {
        username: "Alice".into(),
        email: "Alice@Example.com".into(),
        password_hash: hash_from_your_argon2_code,
    })?;

    match db.get_user_by_username("alice")? {
        Some(u) => { /* verify password against u.password_hash */ }
        None => { /* unknown user */ }
    }
    Ok(())
}
```

Or connect with an explicit URL: `Database::connect("postgresql://...")?`.

## API

All methods take `&mut self` and return `Result<_, DbError>`.

| Method | Returns | Notes |
|--------|---------|-------|
| `Database::connect_from_env()` | `Database` | Reads `DATABASE_URL` |
| `Database::connect(url)` | `Database` | Explicit URL |
| `create_users_table()` | `()` | `CREATE TABLE IF NOT EXISTS` |
| `insert_user(&NewUser)` | `User` | `UsernameTaken` / `EmailTaken` on duplicates; `InvalidInput` on empty fields |
| `get_user_by_id(Uuid)` | `Option<User>` | |
| `get_user_by_username(&str)` | `Option<User>` | Case-insensitive |
| `get_user_by_email(&str)` | `Option<User>` | Case-insensitive |

Normalization (`trim` + lowercase) is done inside the module, so pass usernames and
emails as typed. Password hashing is the caller's job; the module stores the hash it is
given.

`User` has `user_id`, `username`, `email`, `password_hash`, `created_at`, `updated_at`
(`SystemTime`). Its `Debug` output redacts `password_hash`, but never serialize a `User`
straight into an API response.

## Errors

`DbError` variants:

- `Config(String)`: missing or invalid configuration (for example `DATABASE_URL` unset)
- `Connection(String)`: network or TLS failure while connecting
- `Query(String)`: a query or transaction failed
- `InvalidInput(String)`: rejected before reaching the database (empty username, email or hash)
- `UsernameTaken` / `EmailTaken`: unique violation on insert

```rust
match db.insert_user(&new_user) {
    Ok(user) => { /* created */ }
    Err(DbError::UsernameTaken) => { /* 409 */ }
    Err(DbError::EmailTaken) => { /* 409 */ }
    Err(e) => eprintln!("{e}"),
}
```

## Adding queries

1. Create a file such as `sessions.rs` and add `mod sessions;` in `mod.rs`.
2. Add a plain return type (no driver types) and re-export it with `pub use` in `mod.rs`.
3. Add an `impl Database` block. Plain statements use `self.client.query/execute`, and
   `.map_err(DbError::from_pg)` converts errors.
4. For multi-statement atomic work, use `execute_txn(&mut self.client, |txn| { ... })`
   from `txn.rs` (and remove its `#![allow(dead_code)]`). Use `?` on driver calls.
   Return `Err(DbError::...into())` to abort without retry. The closure can run more than
   once, so keep side effects out of it.

## Notes

- **Blocking:** the `postgres` crate is synchronous. Inside async code (Rocket handlers),
  call into this module via `tokio::task::spawn_blocking`, or later move the module to
  `tokio-postgres` internally. Callers won't change.
- **One connection:** `Database` wraps a single client. For concurrent use, add a pool
  (for example `r2d2_postgres`) inside `mod.rs`.
- **TLS:** the connector trusts the system root store. A node with self-signed certs needs
  its CA added in `tls.rs`.