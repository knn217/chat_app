# CockroachDB GitHub Actions integration test

The repository-root workflow `.github/workflows/cockroach-integration.yml` is
manual-only (`workflow_dispatch`, with no inputs). In GitHub, open **Actions**,
select **CockroachDB Integration Test**, and click **Run workflow**.

The job runs on `ubuntu-latest` and:

1. Generates the same local self-signed CA, node certificates, and root client
   certificate as `scripts/generate-certs.sh local`.
2. Starts the existing three-node `docker-compose.yml` cluster.
3. Initializes the cluster once and verifies exactly three registered nodes.
4. Connects from a short-lived CockroachDB CLI container using the generated
   root client certificate over TLS; it creates a database, schema, and table,
   inserts three rows, and asserts the queried count and sum.
5. Always tears down the CI Compose project, deletes its named volumes, and
   removes generated certificate material.

## Run the same test locally

From the repository root:

```bash
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/ci-up.sh
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/ci-test.sh
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/ci-down.sh
```

The CI scripts deliberately use a dedicated Compose project name (`crdb-ci`)
so they do not stop or delete a developer's normal `crdb` local cluster. The
cleanup script deletes the `crdb-ci` project's Docker named volumes, so use it
only for this disposable test cluster.

The test is an integration smoke test, not a production failover, backup,
restore, or performance test. Three containers on one GitHub-hosted VM do not
provide host-level high availability.
