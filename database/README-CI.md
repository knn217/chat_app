# CockroachDB GitHub Actions integration test

The repository-root workflow `.github/workflows/cockroach-integration.yml` is
manual-only (`workflow_dispatch`, with no inputs). In GitHub, open **Actions**,
select **CockroachDB Integration Test**, and click **Run workflow**.

## Run the same test locally

From the repository root:

```bash
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/local-up.sh
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/install-flyway.sh
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/migrate.sh
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/local-test.sh
COMPOSE_PROJECT_NAME=crdb-ci bash database/scripts/local-down.sh
```

The CI scripts deliberately use a dedicated Compose project name (`crdb-ci`)
so they do not stop or delete a developer's normal `crdb` local cluster. The
cleanup script deletes the `crdb-ci` project's Docker named volumes, so use it
only for this disposable test cluster.

The test is an integration smoke test, not a production failover, backup,
restore, or performance test. Three containers on one GitHub-hosted VM do not
provide host-level high availability.
