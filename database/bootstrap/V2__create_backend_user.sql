-- Create user user_be and grant access to all chemas and tables in chat_db
CREATE USER IF NOT EXISTS user_be;

GRANT CONNECT ON DATABASE chat_db TO user_be;

GRANT ALL ON SCHEMA public TO user_be;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO user_be;