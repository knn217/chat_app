# Secure CockroachDB cluster package

A small Docker-based CockroachDB deployment scaffold for Ubuntu. It creates a secure, multi-node CockroachDB cluster with TLS for node-to-node and client-to-node traffic. No database, table, or application schema is created.

This package has two deployment modes:

- **Local development:** three CockroachDB containers on one Docker bridge network, with host ports bound to loopback only.
- **Cloud / real deployment:** one CockroachDB container per Ubuntu VM, using the VM's stable private DNS name/IP and host networking. Each VM has its own persistent data directory.

The local mode is for development and operational rehearsal. Three containers on one physical machine do **not** provide host-level high availability. For production, use at least three separate failure domains where possible, reliable persistent disks, backups, monitoring, and tested recovery procedures.

## 1. Requirements

On each Ubuntu host:

- Docker Engine and the Docker Compose v2 plugin (`docker compose`).
- Network connectivity between every CockroachDB node on TCP **26257** (SQL and inter-node RPC share the default port in this package).
- TCP **8080** for the DB Console only from trusted admin networks, if you need remote console access.
- A stable private DNS name and private IP for each VM. The name used by CockroachDB clients and peers must appear in that node's certificate SAN.
- Synchronized system clocks (NTP/chrony).

Do not expose ports 26257 or 8080 to the public internet. Restrict them with cloud security groups and host firewalls. Prefer private networking/VPN. This package uses self-signed certificates from a private CA; TLS authenticates peers only when clients verify the CA and hostname. Self-signed does not mean unauthenticated.

## 2. Build the distributable package

Run this from the source project directory:

```bash
chmod +x scripts/*.sh
./scripts/package.sh
```

The archive is written to `dist/cockroach-cluster-package.tar.gz`. The packaging script includes the Compose files, scripts, sample configuration, and this README. It intentionally excludes `.env`, generated certificates, the CA private key, database data, and old archives.

On the target Ubuntu host, extract it:

```bash
mkdir -p ~/services/cockroach
 tar -xzf cockroach-cluster-package.tar.gz -C ~/services/cockroach --strip-components=1
cd ~/services/cockroach
cp .env.example .env
```

Edit `.env` to pin the CockroachDB image version you have validated. Do not casually change versions on a running cluster; plan and follow the official upgrade procedure.

## 3. Certificate model (required; no insecure mode)

The scripts call the `cockroach cert` utility inside the same pinned Docker image, so a CockroachDB binary does not need to be installed on the Ubuntu host.

- `secrets/ca.key`: private CA signing key. Keep offline or on a tightly controlled administration machine. **Never copy this file to database VMs or include it in the package archive.**
- `certs/ca/ca.crt`: CA certificate.
- `certs/<node>/`: that node's `ca.crt`, `node.crt`, and `node.key`.
- `certs/client/`: root client certificate and key for administration/application bootstrap.

The generated node certificate is unique per node and includes its node name, DNS name, private IP, and loopback names. The CA key is only needed to issue certificates, not to run nodes.

### Generate certificates for local development

From the extracted package directory:

```bash
./scripts/generate-certs.sh local
```

This reads `config/nodes.local` (node1-node4). The first run creates the CA. The script refuses to overwrite an existing `secrets/ca.key` to avoid accidental CA replacement.

### Generate certificates for cloud VMs

1. On a trusted administration machine, edit `config/nodes.cloud.example` with each node's **stable private DNS name and private IP**. Save it as `config/nodes.cloud`.
2. Ensure the hostnames resolve consistently from all database VMs and from the admin/client hosts that will connect.
3. Generate the CA and node/client certificates:

```bash
./scripts/generate-certs.sh cloud config/nodes.cloud
```

4. Securely distribute only the matching `certs/node1/` directory to node1, `certs/node2/` to node2, etc. Distribute `certs/client/` only to trusted clients. Do not distribute `secrets/ca.key` to database nodes.
5. Set restrictive permissions on the private keys after copying (for example, `chmod 600 certs/*/*.key`). Keep a protected backup of the CA private key separately.

The same CA signs all node and client certificates. If the CA key is lost, existing certificates continue to work, but you cannot issue replacements without a planned CA recovery/rotation process.

## 4. Local development: start a three-node cluster

From the extracted package directory:

```bash
cp .env.example .env
./scripts/generate-certs.sh local
docker compose pull
docker compose up -d
```

Initialize the cluster **once**, after all three nodes are running:

```bash
./scripts/init-cluster.sh node1
```

Do not run `cockroach init` again on an already initialized cluster. Check containers and node membership:

```bash
docker compose ps
./scripts/status.sh
```

Local endpoints (bound to `127.0.0.1` only):

| Node | SQL/TLS | DB Console/TLS |
|---|---:|---:|
| node1 | `localhost:26257` | `https://localhost:8080` |
| node2 | `localhost:26258` | `https://localhost:8081` |
| node3 | `localhost:26259` | `https://localhost:8082` |

The browser will not automatically trust this private CA. Import `certs/ca/ca.crt` into a trusted browser/OS trust store if you want to remove the certificate warning; otherwise verify the certificate fingerprint before proceeding. Keep the console bound to loopback unless you deliberately configure a trusted admin-only access path.

Open a SQL shell using the generated root client certificate:

```bash
./scripts/sql.sh node1
# or: ./scripts/sql.sh node2
```

For an application, connect to one or more SQL endpoints using TLS and the client certificate/key. Use `sslmode=verify-full`, `sslrootcert=ca.crt`, `sslcert=client.<user>.crt`, and `sslkey=client.<user>.key`; the hostname in the connection string must match a certificate SAN. Prefer a private DNS name over an IP if that is how the service discovers database nodes.

## 5. Cloud deployment: three Ubuntu VMs

This mode runs **one node per VM**. Do not use the local `docker-compose.yml` for multiple cloud hosts; a Docker bridge network does not span hosts.

### 5.1 Prepare networking and files

Assume `db-1.internal.example`, `db-2.internal.example`, and `db-3.internal.example` resolve to private IPs. Configure firewall/security-group rules:

- Allow TCP 26257 between the database VMs, and from explicitly approved application/client networks.
- Allow TCP 8080 only from approved administrator networks, or keep it inaccessible remotely and use SSH tunneling.
- Deny public internet access to both ports.

Extract the same package on each VM, copy the correct per-node certificate directory into `certs/<NODE_NAME>/`, and create its local data directory:

```bash
mkdir -p data/node1
```

Replace `node1` with the VM's configured node name. Copy `docker-compose.cloud.yml`, `scripts/`, and the required certs to every VM. The CA private key must not be present on the VMs.

### 5.2 Start node1

On db-1:

```bash
export NODE_NAME=node1
export NODE_ADVERTISE_ADDR=db-1.internal.example
export JOIN_ADDRS=db-1.internal.example:26257,db-2.internal.example:26257,db-3.internal.example:26257
export COCKROACH_IMAGE=cockroachdb/cockroach:v26.2.2
docker compose -f docker-compose.cloud.yml up -d
```

### 5.3 Start node2 and node3

Run the same command on each remaining VM, changing `NODE_NAME` and `NODE_ADVERTISE_ADDR` to that VM's own name and DNS name. Keep `JOIN_ADDRS` identical on all nodes. For example, on db-2:

```bash
export NODE_NAME=node2
export NODE_ADVERTISE_ADDR=db-2.internal.example
export JOIN_ADDRS=db-1.internal.example:26257,db-2.internal.example:26257,db-3.internal.example:26257
export COCKROACH_IMAGE=cockroachdb/cockroach:v26.2.2
docker compose -f docker-compose.cloud.yml up -d
```

Repeat for node3. The node certificate directory mounted at `./certs/${NODE_NAME}` must match that node's name and advertise DNS/IP SANs.

### 5.4 Initialize once

After all three nodes are started, initialize from one node (node1 shown):

```bash
docker exec -it cockroach-node1 ./cockroach init \
  --certs-dir=/cockroach/certs \
  --host=db-1.internal.example:26257
```

Run this only once for a brand-new cluster. Check membership:

```bash
docker exec -it cockroach-node1 ./cockroach node status \
  --certs-dir=/cockroach/certs --host=db-1.internal.example:26257
```

Persist the environment variables in a root-owned deployment env file or systemd/automation configuration rather than relying on interactive shell exports. Do not store secrets in shell history.

## 6. Cluster operations

### View status and logs

**Local:**

```bash
./scripts/status.sh
docker compose logs -f node1
```

**Cloud (run on a node):**

```bash
docker exec -it cockroach-node1 ./cockroach node status \
  --certs-dir=/cockroach/certs --host=db-1.internal.example:26257
docker logs -f cockroach-node1
```

### Stop and restart one node for maintenance

Before stopping a node, check cluster health and ensure the remaining nodes retain quorum. A three-voter cluster normally tolerates one unavailable node, not two. Stop gracefully; the Compose service has a five-minute stop grace period.

**Local:**

```bash
docker compose stop -t 300 node3
docker compose start node3
```

**Cloud:**

On the target VM:

```bash
docker compose -f docker-compose.cloud.yml stop -t 300 cockroach
docker compose -f docker-compose.cloud.yml start cockroach
```

The data volume/directory and node identity are preserved. A normal restart is not a node replacement; do not delete its data.

### Add a node (horizontal capacity)

CockroachDB automatically distributes ranges and replicas according to its replication/placement settings. Adding a node does not require creating tables or manually sharding data. This is distributed SQL with automatic range splitting, replication, and rebalancing; it is not application-managed hash sharding.

**Local development (node4):**

`config/nodes.local` already includes node4. Generate certs before first start, then:

```bash
docker compose -f docker-compose.yml -f docker-compose.extra-node.yml up -d node4
```

The extra node joins via node1-node3. Verify using `./scripts/status.sh` or `cockroach node status` inside node1. If certs were already generated before node4 was added to the nodes file, generate a node4 certificate separately with the same CA (do not regenerate the CA); use the documented `cockroach cert create-node` command with `secrets/ca.key` on the secure admin machine.

**Cloud:**

1. Add the new node's name, stable private DNS name, and private IP to the admin-side node inventory; issue its node certificate using the existing CA key.
2. Distribute only its node certificate directory to the new VM. Prepare the VM, Docker, firewall, persistent disk, and `data/<new-node>` directory.
3. Start `docker-compose.cloud.yml` on the new VM with its own `NODE_NAME` and `NODE_ADVERTISE_ADDR`. Use the existing healthy node addresses in `JOIN_ADDRS` (the original three seed addresses are fine while reachable).
4. Do **not** run `cockroach init` on the new node. Verify that it appears in `node status` and wait for rebalancing to settle.

### Decommission and remove a node

Do not simply delete a live node's data directory or container if you intend to remove it from the cluster. First obtain its node ID and decommission it while the cluster is healthy. Decommissioning transfers replicas away where possible; wait for completion.

**Local (example node3; substitute its actual node ID):**

```bash
docker compose exec node1 ./cockroach node status \
  --certs-dir=/cockroach/certs --host=node1:26257
# Replace <NODE_ID> with node3's ID from the status output.
docker compose exec node1 ./cockroach node decommission <NODE_ID> \
  --certs-dir=/cockroach/certs --host=node1:26257 --wait=all

docker compose stop -t 300 node3
docker compose rm -f node3
```

**Cloud:**

```bash
docker exec -it cockroach-node1 ./cockroach node status \
  --certs-dir=/cockroach/certs --host=db-1.internal.example:26257
docker exec -it cockroach-node1 ./cockroach node decommission <NODE_ID> \
  --certs-dir=/cockroach/certs --host=db-1.internal.example:26257 --wait=all
```

After decommission completes, stop the CockroachDB service on the target VM. Retain its data directory and VM snapshot until your retention policy allows deletion. Confirm the cluster is healthy and the node is decommissioned before destroying storage.

If a node is permanently lost and cannot be contacted, do not blindly use the normal decommission command or delete metadata. Follow CockroachDB's documented dead-node replacement/recovery procedure for your exact version and verify quorum first.

### Replace a node

A replacement is a new CockroachDB node identity with a fresh, empty store. Never attach a different node to a copied live node store as a shortcut.

**Local:**

1. Decommission the old node as above and wait for completion.
2. Stop/remove its container. Remove its old named volume only after decommission and after taking any required backup. For node3, the volume name is normally `<compose-project>_node3-data` (check `docker volume ls`).
3. Recreate the service with a fresh volume and the appropriate node certificate. If reusing the same DNS name, its node cert SAN must still match; otherwise issue a new certificate for the replacement name/IP using the existing CA.
4. Start it and verify it rejoins. Do not run `init` again.

**Cloud:**

1. Decommission the old node if it is reachable; if it is dead, use the documented dead-node recovery procedure.
2. Provision a replacement VM and fresh persistent disk/data directory.
3. Issue a node certificate for the replacement's stable DNS name and IP, distribute it, and start it with the cluster's seed `JOIN_ADDRS`.
4. Verify membership and allow rebalancing to complete before retiring old disks/snapshots.

### Shut down the whole cluster

A whole-cluster shutdown is different from stopping one node. It makes the database unavailable; start all nodes again to restore service. Stop all nodes gracefully, preferably in a controlled sequence after checking that no maintenance or backup job is active.

**Local:**

```bash
docker compose stop -t 300
```

**Cloud:**

Run on every VM:

```bash
docker compose -f docker-compose.cloud.yml stop -t 300 cockroach
```

To restart, use `docker compose start` locally or `docker compose -f docker-compose.cloud.yml start cockroach` on each VM. Preserve all data directories and certificates. Do not run `init` again.

### Destroy a local development cluster (irreversible)

This removes containers and named data volumes. It is not a normal shutdown.

```bash
docker compose down -v
# If the optional node4 was used:
docker compose -f docker-compose.yml -f docker-compose.extra-node.yml down -v
```

The generated certs and CA key remain on disk unless you explicitly delete them. Never run destructive volume commands on a production host as a cleanup shortcut.

## 7. Backups, replication, and sharding notes

- CockroachDB distributes data as ranges and replicates them using Raft. Adding nodes provides more compute/storage capacity and triggers rebalancing; it does not guarantee every workload scales linearly.
- The default replication factor is typically three replicas. Three nodes across separate failure domains are a sensible minimum for a resilient starting point; actual survival depends on replica placement and cluster topology.
- Node count is not a substitute for backups. Configure and test scheduled backups to durable object storage outside the cluster, and test restores.
- Use dedicated persistent disks with appropriate IOPS/latency. Avoid ephemeral container writable layers.
- For production, review the official production checklist, monitoring/alerting, certificate rotation, rolling upgrade, backup/restore, and capacity planning documentation.

## 8. Certificate rotation and security reminders

The package does not automate certificate rotation. Monitor expiry and rotate node/client certificates before they expire. Keep CA private-key access restricted. Back up the CA key encrypted and separately from database hosts. For CA rotation, follow CockroachDB's documented trust-transition procedure; do not simply replace `ca.crt` on all nodes at once.

The root client certificate is highly privileged. For applications, issue a dedicated SQL user and client certificate with least-privilege SQL grants; do not use the root certificate in application services. Protect private keys (`chmod 600`) and distribute only the certificates each host/client needs.

## 9. Official references

- [The Docker cluster tutorial supplied for this package](https://docs.cockroachlabs.com/docs/stable/start-a-local-cluster-in-docker-mac) (its example is explicitly insecure; this package preserves the topology concept but replaces insecure mode with TLS certificates).
- [CockroachDB secure a cluster](https://www.cockroachlabs.com/docs/stable/secure-a-cluster.html)
- [Create security certificates](https://www.cockroachlabs.com/docs/stable/create-security-certificates.html)
- [Manual deployment](https://www.cockroachlabs.com/docs/stable/deploy-cockroachdb-on-premises.html)
- [Production checklist](https://www.cockroachlabs.com/docs/stable/recommended-production-settings.html)
- [Node decommissioning](https://www.cockroachlabs.com/docs/stable/remove-nodes.html)
