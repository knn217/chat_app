-- Refresh tokens for the backend. Must stay idempotent (re-run on every setup).
--
-- The client holds a random 256-bit token; only its SHA-256 hash is stored, so a
-- database leak does not leak usable tokens. A token is single-use: refreshing
-- sets revoked_at and issues a new one (rotation). Random hashes also spread
-- inserts across ranges, like the random user_id.
--
-- Expired and revoked rows are not deleted yet (the app role has no DELETE).

CREATE TABLE IF NOT EXISTS refresh_tokens (
    token_hash BYTES       NOT NULL,
    user_id    UUID        NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT refresh_tokens_pkey PRIMARY KEY (token_hash)
);

CREATE INDEX IF NOT EXISTS refresh_tokens_user_id_idx ON refresh_tokens (user_id);
