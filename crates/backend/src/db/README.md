# db module

Barebone **async** query layer for CockroachDB (Postgres wire protocol). It is the only code
that knows about `tokio_postgres`, `openssl`, `argon2` or SQL. Callers use `Database`, plain
data types and `DbError`, so the driver can be swapped without touching any caller.

## Layout

| File | Purpose |
|------|---------|
| `mod.rs` | `Database` (owns the client), `connect_from_env()`, `connect(url)`; re-exports |
| `users.rs` | `users` auth table: `User`, `NewUser`, insert, authenticate, lookups |
| `password.rs` | Private Argon2id hashing and verification (runs on the blocking pool) |
| `error.rs` | `DbError`, the only error type callers see |
| `tls.rs` | Private openssl TLS connector |

## Setup

Add to `Cargo.toml`:

```toml
tokio-postgres = { version = "0.7", features = ["with-uuid-1"] }
postgres-openssl = "0.5"
openssl = "0.10"
uuid = "1"
argon2 = { version = "0.5", features = ["std"] }
tokio = { version = "1", features = ["rt"] }
```

Copy the folder into your crate as `src/db/` and declare it:

```rust
mod db;
```

`Database::connect_from_env()` reads `DATABASE_URL`, for example:

```
postgresql://user:password@host:26257/dbname?sslmode=require
```

Or connect with an explicit URL: `Database::connect("postgresql://...").await?`.

## Async rules

Every method that touches the database is `async`: always `.await` it, from inside a tokio
runtime (actix-web's runtime is one). All methods take `&self`, so a single `Database`
can be shared by request handlers and background tasks without a `Mutex`.

- Create the `Database` **once at startup**, inside `main` (under `#[actix_web::main]`), and
  share it. Don't create it per request or inside the `HttpServer::new` closure.
- Never call it from plain sync code and never wrap it in `block_on` / `Runtime::new()`.
  Starting a runtime inside a runtime panics with "Cannot start a runtime from within a
  runtime".
- Don't pass a `&mut`-style handle around. Share via `web::Data<Database>` or `Arc<Database>`.

## Usage: REST handler (actix-web)

```rust
use actix_web::{web, App, HttpResponse, HttpServer};

mod db;
use db::{Database, DbError, NewUser};

#[derive(serde::Deserialize)]
struct SignUp {
    username: String,
    email: String,
    password: String,
}

// POST /signup
async fn sign_up(db: web::Data<Database>, body: web::Json<SignUp>) -> HttpResponse {
    let body = body.into_inner();
    let new = NewUser {
        username: body.username,
        email: body.email,
        password: body.password, // plaintext, the module hashes it
    };
    match db.insert_user(&new).await {
        Ok(user) => HttpResponse::Created().body(user.user_id.to_string()),
        Err(DbError::UsernameTaken | DbError::EmailTaken) => HttpResponse::Conflict().finish(),
        Err(DbError::InvalidInput(msg)) => HttpResponse::BadRequest().body(msg),
        Err(e) => {
            eprintln!("signup failed: {e}");
            HttpResponse::InternalServerError().finish()
        }
    }
}

#[derive(serde::Deserialize)]
struct Login {
    username: String,
    password: String,
}

// POST /login
async fn login(db: web::Data<Database>, body: web::Json<Login>) -> HttpResponse {
    match db.authenticate_by_username(&body.username, &body.password).await {
        Ok(Some(user)) => HttpResponse::Ok().body(user.user_id.to_string()),
        Ok(None) => HttpResponse::Unauthorized().finish(), // unknown user or wrong password
        Err(e) => {
            eprintln!("login failed: {e}");
            HttpResponse::InternalServerError().finish()
        }
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Connect once, here, inside the runtime.
    let db = Database::connect_from_env()
        .await
        .expect("failed to connect to database");
    db.create_users_table()
        .await
        .expect("failed to create users table");

    let db = web::Data::new(db);
    HttpServer::new(move || {
        App::new()
            .app_data(db.clone()) // cheap Arc clone per worker
            .route("/signup", web::post().to(sign_up))
            .route("/login", web::post().to(login))
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
```

## Usage: server-internal code (no REST)

The same `Database` works from background tasks and other internal code. Share it as an `Arc`
(`web::Data<Database>` is one, use `.into_inner()`):

```rust
use std::sync::Arc;

let db: Arc<Database> = db.into_inner();

// e.g. a background task
let task_db = Arc::clone(&db);
tokio::spawn(async move {
    match task_db.get_user_by_id(some_user_id).await {
        Ok(Some(user)) => println!("found {}", user.username),
        Ok(None) => println!("no such user"),
        Err(e) => eprintln!("lookup failed: {e}"),
    }
});
```

Outside of actix, the same code works under `#[tokio::main]`.

## API

All methods are `async` and take `&self`.

| Method | Returns | Notes |
|--------|---------|-------|
| `Database::connect_from_env()` | `Database` | Reads `DATABASE_URL` |
| `Database::connect(url)` | `Database` | Explicit URL |
| `create_users_table()` | `()` | `CREATE TABLE IF NOT EXISTS` |
| `insert_user(&NewUser)` | `User` | Hashes the password; `UsernameTaken` / `EmailTaken` on duplicates; `InvalidInput` on empty fields |
| `authenticate_by_username(username, password)` | `Option<User>` | `None` for unknown user or wrong password |
| `authenticate_by_email(email, password)` | `Option<User>` | Same, identified by email |
| `get_user_by_id(Uuid)` | `Option<User>` | No password check |
| `get_user_by_username(&str)` | `Option<User>` | Case-insensitive, no password check |
| `get_user_by_email(&str)` | `Option<User>` | Case-insensitive, no password check |

Normalization (`trim` + lowercase) and hashing both happen inside the module. Callers pass
usernames and emails as typed, and passwords in plaintext.

`User` has `user_id`, `username`, `email`, `created_at`, `updated_at` (`SystemTime`). It
carries no password data. `NewUser`'s `Debug` output redacts `password`.

## Passwords

- Hashing is Argon2id (the `argon2` crate defaults) with a random salt. The stored value is
  a PHC string, so salt and parameters travel with the hash.
- Hashing and verification are CPU-heavy (tens of milliseconds), so the module runs them on
  tokio's blocking pool. Async worker threads are not stalled.
- `authenticate_*` returns `None` for both "no such user" and "wrong password". For an
  unknown user it still performs a dummy verification, so response time doesn't reveal which
  usernames or emails exist.

## Errors

`DbError` variants:

- `Config(String)`: missing or invalid configuration (for example `DATABASE_URL` unset)
- `Connection(String)`: network or TLS failure while connecting
- `Query(String)`: a query failed
- `InvalidInput(String)`: rejected before reaching the database (empty username, email or password)
- `Hash(String)`: hashing or verification failed (for example a malformed stored hash)
- `UsernameTaken` / `EmailTaken`: unique violation on insert

## Adding queries

1. Create a file such as `sessions.rs` and add `mod sessions;` in `mod.rs`.
2. Add a plain return type (no driver types) and re-export it with `pub use` in `mod.rs`.
3. Add an `impl Database` block with `async fn`s taking `&self`, using
   `self.client.query/execute(...).await` and `.map_err(DbError::from_pg)` for errors.
4. Multi-statement atomic work needs a transaction (`&mut` on the client) and CockroachDB
   retry handling. The old retry helper was removed with the sync driver. Add an async one
   when the first query needs it.

## Notes

- **One connection:** `Database` wraps a single connection driven by a background task. It
  does not reconnect: if the connection drops, calls return `DbError::Query`. When you need
  more throughput or resilience, add a pool (for example `deadpool-postgres`) inside
  `mod.rs`. Callers won't change.
- **TLS:** the connector trusts the system root store. A node with self-signed certs needs
  its CA added in `tls.rs`.