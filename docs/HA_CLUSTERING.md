# Neo4j High Availability & Clustering

## 1. Cluster Topology

Production topology for this assessment (lab Compose remains single-node for local demos):

- **3 Raft core members** (primary + 2 secondaries) across 3 availability zones
- **2 read replicas** dedicated to analytics / blast-radius queries
- **1 standalone read replica** reserved for backup operations only

```
  ┌─────────────────────────────────────────────────────────┐
  │                    BOLT ROUTER                          │
  │        (auto-discovered by Neo4j driver)                │
  └──────┬──────────────────┬──────────────────┬───────────┘
         │ Writes           │ Reads            │ Analytics
         ▼                  ▼                  ▼
  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐
  │   PRIMARY   │  │  SECONDARY   │  │  READ REPLICA    │
  │  (Leader)   │  │  (Follower)  │  │  (Async replica) │
  │ us-east-1a  │  │ us-east-1b   │  │  eu-west-1       │
  └──────┬──────┘  └──────┬───────┘  └──────────────────┘
         │                │
         └────────────────┘
              Raft consensus
         (majority ACK required)
```

Implementation references: `admin/backup.sh`, `admin/restore.sh`, `admin/cluster_health_check.sh`, `admin/rbac_setup.cypher`, `architecture/SCALE_DESIGN.md`.

## 2. How Causal Clustering Works

Raft consensus in Neo4j Causal Cluster:

- Every write goes to the **primary leader**
- Primary replicates to followers; the write is ACKed once a **majority (2 of 3)** confirms
- The cluster tolerates **1 core member failure** without losing write capability
- **Election timeout:** ~7 seconds. A new leader is elected if the primary becomes unreachable
- **Bookmark mechanism:** the driver uses causal consistency bookmarks so a read after a write sees the same or later transaction version

## 3. Read/Write Routing Behavior

How the Neo4j Python (and Java) driver routes queries:

- **WRITE session** → always routed to primary
- **READ session** → load-balanced across members in the routing table
- `session.execute_read()` → safe to retry on transient failure; may go to a secondary/replica
- `session.execute_write()` → goes to primary; retried on transient failure
- Routing table is refreshed every **300 seconds** by default

Python driver configuration that enables routing:

```python
driver = GraphDatabase.driver(
    "neo4j://neo4j-primary:7687",   # neo4j:// scheme = routing enabled
    auth=(user, password),
    max_connection_pool_size=50,
)
```

Contrast with `bolt://` (single server, no routing table, no automatic failover).

This project's `Neo4jClient` uses `execute_read` / `execute_write` so write paths stay on the primary and reads can use secondaries when a `neo4j://` URI is configured.

## 4. Failure Handling Scenarios

### Scenario A — Primary fails

- Raft detects missed heartbeats within election timeout (~7s)
- Remaining secondaries hold election; one becomes new primary
- Bolt router discovers new topology on next routing table refresh
- Applications with `neo4j://` reconnect automatically
- **Data loss:** zero (writes were ACKed by majority before the primary failed)
- **DBA action:** investigate failed node; rejoin as secondary after repair

### Scenario B — One secondary fails

- No write impact (primary + 1 remaining secondary = still quorum)
- Read capacity drops; routing table adjusts automatically
- **DBA action:** repair and rejoin; urgency rises only if a second core is at risk

### Scenario C — Network partition (minority side)

- Minority partition (1 node) cannot reach quorum → becomes read-only
- Prevents split-brain writes (a partition that cannot ACK writes refuses them)
- **DBA action:** restore network; minority node catches up via Raft log replay

### Scenario D — Read replica fails

- Zero impact on quorum writes/reads
- Analytics queries may slow if load shifts to remaining replicas
- **DBA action:** repair and rejoin; replica catches up asynchronously

## 5. Safe Rolling Upgrade Procedure

Exact steps, in order:

1. Confirm cluster health: `CALL dbms.cluster.overview()`
2. Upgrade **read replicas** first (zero quorum risk)
   - Stop replica: `neo4j stop`
   - Upgrade binaries
   - Start: `neo4j start`
   - Verify: `CALL dbms.cluster.role()` returns `READ_REPLICA`
3. Upgrade **secondaries** one at a time
   - Wait for previous node to fully rejoin before touching the next
   - Check: `SHOW DATABASES YIELD name, currentStatus WHERE currentStatus <> 'online'`
4. **Step down** the primary before upgrading it
   - `CALL dbms.cluster.stepDown()` — triggers new election
   - Verify the old primary is now a secondary: `CALL dbms.cluster.role()`
5. Upgrade the former primary
6. Final verification: `SHOW DATABASES` all online; `CALL dbms.cluster.overview()` all members visible

**Never** upgrade more than one core member simultaneously.  
**Never** skip the step-down before upgrading the primary.

## 6. Monitoring a Cluster

Key metrics during and after maintenance:

- `neo4j.cluster.discovery.unreachable_members` — must be 0
- `neo4j.cluster.raft.replication.lag` — should be < 5000ms; > 30000ms = alert
- `neo4j.db.transaction.active` — watch for spike after failover (queued writes)
- `neo4j.db.page_cache.hit_ratio` — may dip on new primary (cold cache)

Commands after any failover:

```cypher
CALL dbms.cluster.overview()     -- verify all members and roles
SHOW DATABASES YIELD name, currentStatus, statusMessage
CALL dbms.listTransactions()     -- check for stuck transactions from failover
```

Also run: `admin/cluster_health_check.sh --format text --expected-role PRIMARY --min-members 3`.

## 7. Backup in a Cluster

- Always run backups against a **read replica**, never the primary
- Isolates backup I/O from the production write path
- Prefer the dedicated backup read replica in this topology
- Command shape: `neo4j-admin database backup --from=<replica-bolt-address>`
- Transaction logs are pruned only after a successful backup checkpoint
- Disk can grow during backup failures — see `admin/backup.sh` and Datadog disk alerts
