mod db;
use db::{Database, DbError, NewUser};

fn main() -> Result<(), DbError> {
    let mut db = Database::connect_from_env()?;
    db.create_users_table()?;

    let _user = db.insert_user(&NewUser {
        username: "Alice".into(),
        email: "Alice@Example.com".into(),
        password_hash: "this is an example hash".into(),
    })?;

    match db.get_user_by_username("alice")? {
        Some(_u) => { /* verify password against u.password_hash */ }
        None => { /* unknown user */ }
    }
    Ok(())
}
