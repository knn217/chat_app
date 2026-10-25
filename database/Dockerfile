# Thin wrapper around the official CockroachDB image that bakes in the setup
# scripts and SQL. Both compose services use this one image.
ARG COCKROACH_VERSION
FROM cockroachdb/cockroach:${COCKROACH_VERSION}

COPY scripts/ /chat-db/scripts/
COPY sql/ /chat-db/sql/

# Scripts are run through sh, so no executable bit is needed.
ENTRYPOINT ["/bin/sh"]
CMD ["/chat-db/scripts/start-node.sh"]
