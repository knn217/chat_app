mod db;
use db::{Database, DbError};

fn main() -> Result<(), DbError> {
    let mut db = Database::connect_from_env()?;

    db.create_accounts_table()?;
    let a = db.insert_account(1000)?;
    let b = db.insert_account(250)?;

    db.transfer_funds(a, b, 100)?;

    for acc in db.list_accounts()? {
        println!("{} {}", acc.id, acc.balance);
    }
    Ok(())
}
