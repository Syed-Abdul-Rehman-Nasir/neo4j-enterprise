#!/usr/bin/env bash
# =============================================================================
# admin/restore.sh — Production Neo4j database restore
# chmod +x admin/restore.sh
#
# Usage:
#   ./restore.sh --backup-path <path> --target-database <name> [--dry-run]
#
# RPO (Recovery Point Objective): 1 hour (incremental backup frequency)
# RTO (Recovery Time Objective): ~30 minutes (restore + validation + traffic rerouting)
# Backup validation: run restore to isolated environment monthly to verify recoverability
#
# Required environment:
#   NEO4J_HOME, NEO4J_USERNAME, NEO4J_PASSWORD
# Optional:
#   NEO4J_URI (default bolt://localhost:7687), EXPECTED_MIN_NODES (default 30)
# =============================================================================

# set -e: exit on first command failure
# set -u: fail on unset variables
# set -o pipefail: fail if any command in a pipeline fails
set -euo pipefail

BACKUP_PATH=""
TARGET_DATABASE=""
DRY_RUN=0

NEO4J_HOME="${NEO4J_HOME:-}"
NEO4J_URI="${NEO4J_URI:-bolt://localhost:7687}"
NEO4J_USERNAME="${NEO4J_USERNAME:-neo4j}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-}"
EXPECTED_MIN_NODES="${EXPECTED_MIN_NODES:-30}"

NEO4J_ADMIN=""
CYPHER_SHELL=""

RESTORE_START_EPOCH=0
RESTORE_END_EPOCH=0
NODES_BEFORE=""
NODES_AFTER=""
RESTORE_STATUS="FAILURE"
KNOWN_NODE_OK="no"

usage() {
  cat <<EOF
Usage: $0 --backup-path <path> --target-database <name> [--dry-run]

  --backup-path       Local path (or downloaded artifact) of the Neo4j backup
  --target-database   Destination database name to overwrite
  --dry-run           Validate inputs and print plan; do not overwrite
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backup-path)
      BACKUP_PATH="${2:-}"
      shift 2
      ;;
    --target-database)
      TARGET_DATABASE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

log() {
  local level="$1"
  shift
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [${level}] $*"
}

fail() {
  log "ERROR" "$*"
  RESTORE_STATUS="FAILURE"
  generate_restore_report || true
  exit 1
}

cypher() {
  local database="${1:-system}"
  shift
  "${CYPHER_SHELL}" -a "${NEO4J_URI}" -u "${NEO4J_USERNAME}" -p "${NEO4J_PASSWORD}" -d "${database}" --format plain "$@"
}

# ---------------------------------------------------------------------------
# 1. validate_inputs
# ---------------------------------------------------------------------------
validate_inputs() {
  log "INFO" "Validating inputs..."

  if [[ -z "${BACKUP_PATH}" ]]; then
    fail "--backup-path is required"
  fi
  if [[ -z "${TARGET_DATABASE}" ]]; then
    fail "--target-database is required"
  fi
  if [[ ! -e "${BACKUP_PATH}" ]]; then
    fail "Backup path does not exist: ${BACKUP_PATH}"
  fi

  # Valid Neo4j database name: letters, digits, dots, dashes; start with letter
  if [[ ! "${TARGET_DATABASE}" =~ ^[A-Za-z][A-Za-z0-9.-]*$ ]]; then
    fail "Invalid target database name: '${TARGET_DATABASE}' (must start with a letter; use A-Z, a-z, 0-9, '.', '-')"
  fi
  if [[ "${TARGET_DATABASE}" == "system" ]]; then
    fail "Refusing to restore over the system database"
  fi

  : "${NEO4J_HOME:?NEO4J_HOME must be set}"
  : "${NEO4J_PASSWORD:?NEO4J_PASSWORD must be set for cypher-shell}"

  NEO4J_ADMIN="${NEO4J_HOME}/bin/neo4j-admin"
  CYPHER_SHELL="${NEO4J_HOME}/bin/cypher-shell"
  if [[ ! -x "${NEO4J_ADMIN}" ]]; then
    command -v neo4j-admin >/dev/null 2>&1 || fail "neo4j-admin not found"
    NEO4J_ADMIN="$(command -v neo4j-admin)"
  fi
  if [[ ! -x "${CYPHER_SHELL}" ]]; then
    command -v cypher-shell >/dev/null 2>&1 || fail "cypher-shell not found"
    CYPHER_SHELL="$(command -v cypher-shell)"
  fi

  log "INFO" "Inputs OK (backup=${BACKUP_PATH}, target=${TARGET_DATABASE}, dry_run=${DRY_RUN})"
}

# ---------------------------------------------------------------------------
# 2. confirm_restore
# ---------------------------------------------------------------------------
confirm_restore() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "INFO" "DRY-RUN: skipping overwrite confirmation"
    return 0
  fi

  echo
  echo "This will OVERWRITE the target database. Type the database name to confirm:"
  read -r confirmation
  if [[ "${confirmation}" != "${TARGET_DATABASE}" ]]; then
    fail "Confirmation mismatch (typed '${confirmation}', expected '${TARGET_DATABASE}'); aborting"
  fi
  log "INFO" "Overwrite confirmed for database '${TARGET_DATABASE}'"
}

# ---------------------------------------------------------------------------
# Capture node count helper
# ---------------------------------------------------------------------------
count_nodes() {
  local database="$1"
  set +e
  local out
  out="$(cypher "${database}" "MATCH (n) RETURN count(n) AS c;" 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
  local rc=$?
  set -e
  if [[ "${rc}" -ne 0 || -z "${out}" || ! "${out}" =~ ^[0-9]+$ ]]; then
    echo "unavailable"
  else
    echo "${out}"
  fi
}

# ---------------------------------------------------------------------------
# 3. stop_connections
# ---------------------------------------------------------------------------
stop_connections() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "INFO" "DRY-RUN: would kill connections to '${TARGET_DATABASE}'"
    return 0
  fi

  log "INFO" "Stopping active connections for database '${TARGET_DATABASE}'..."

  # Neo4j 5: list connections then kill by connectionId (best-effort)
  set +e
  cypher "system" \
    "SHOW CONNECTIONS YIELD connectionId, database WHERE database = '${TARGET_DATABASE}' RETURN connectionId;" \
    2>/dev/null | while read -r cid; do
      [[ "${cid}" =~ ^[a-zA-Z0-9-]+$ ]] || continue
      cypher "system" "CALL dbms.killConnection('${cid}');" >/dev/null 2>&1 || true
    done

  # Also terminate transactions on the target database when available
  cypher "system" \
    "SHOW TRANSACTIONS YIELD transactionId, database WHERE database = '${TARGET_DATABASE}' CALL dbms.killTransaction(transactionId) YIELD message RETURN message;" \
    >/dev/null 2>&1 || true
  set -e

  log "INFO" "Connection/transaction termination attempted for '${TARGET_DATABASE}'"
}

# ---------------------------------------------------------------------------
# 4. perform_restore
# ---------------------------------------------------------------------------
perform_restore() {
  NODES_BEFORE="$(count_nodes "${TARGET_DATABASE}")"
  log "INFO" "Node count before restore: ${NODES_BEFORE}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "INFO" "DRY-RUN: would run: neo4j-admin database restore --from-path=${BACKUP_PATH} --overwrite-destination=true ${TARGET_DATABASE}"
    NODES_AFTER="${NODES_BEFORE}"
    RESTORE_STATUS="DRY_RUN"
    return 0
  fi

  log "INFO" "Restoring '${TARGET_DATABASE}' from ${BACKUP_PATH} (overwrite-destination)..."
  RESTORE_START_EPOCH="$(date +%s)"

  "${NEO4J_ADMIN}" database restore \
    --from-path="${BACKUP_PATH}" \
    --overwrite-destination=true \
    "${TARGET_DATABASE}"

  RESTORE_END_EPOCH="$(date +%s)"
  log "INFO" "neo4j-admin database restore completed"

  # Ensure database is online for smoke tests
  set +e
  cypher "system" "START DATABASE ${TARGET_DATABASE};" >/dev/null 2>&1 || true
  set -e
}

# ---------------------------------------------------------------------------
# 5. validate_restored_data
# ---------------------------------------------------------------------------
validate_restored_data() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "INFO" "DRY-RUN: skipping smoke tests"
    return 0
  fi

  log "INFO" "Running smoke tests against '${TARGET_DATABASE}'..."

  # Allow DBMS a moment after START DATABASE
  sleep 2

  NODES_AFTER="$(count_nodes "${TARGET_DATABASE}")"
  log "INFO" "Node count after restore: ${NODES_AFTER}"

  if [[ "${NODES_AFTER}" == "unavailable" ]]; then
    fail "Smoke test failed: could not query node count on '${TARGET_DATABASE}'"
  fi
  if [[ "${NODES_AFTER}" -lt "${EXPECTED_MIN_NODES}" ]]; then
    fail "Smoke test failed: node count ${NODES_AFTER} < expected minimum ${EXPECTED_MIN_NODES}"
  fi

  set +e
  local known
  known="$(cypher "${TARGET_DATABASE}" \
    "MATCH (e:Employee {employeeId: 'EMP-001'}) RETURN e.name AS name;" 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
  set -e

  if [[ "${known}" == *"Alice"* || "${known}" == "AliceMercer" ]]; then
    KNOWN_NODE_OK="yes"
    log "INFO" "Known node check passed (EMP-001 present)"
  else
    # Accept any non-empty name for EMP-001 if sample data naming differs
    if [[ -n "${known}" && "${known}" != "name" ]]; then
      KNOWN_NODE_OK="yes"
      log "INFO" "Known node check passed (EMP-001 name='${known}')"
    else
      fail "Smoke test failed: known node Employee EMP-001 not found"
    fi
  fi

  RESTORE_STATUS="SUCCESS"
}

# ---------------------------------------------------------------------------
# 6. generate_restore_report
# ---------------------------------------------------------------------------
generate_restore_report() {
  local duration="n/a"
  if [[ "${RESTORE_START_EPOCH}" -gt 0 && "${RESTORE_END_EPOCH}" -gt 0 ]]; then
    duration="$((RESTORE_END_EPOCH - RESTORE_START_EPOCH))s"
  fi

  cat <<EOF

======== Neo4j Restore Report ========
Backup source:     ${BACKUP_PATH}
Target database:   ${TARGET_DATABASE}
Dry run:           ${DRY_RUN}
Restore time:      ${duration}
Node count before: ${NODES_BEFORE:-n/a}
Node count after:  ${NODES_AFTER:-n/a}
Known node OK:     ${KNOWN_NODE_OK}
Status:            ${RESTORE_STATUS}
Generated (UTC):   $(date -u +'%Y-%m-%dT%H:%M:%SZ')
======================================

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  validate_inputs
  confirm_restore
  stop_connections
  perform_restore
  validate_restored_data
  generate_restore_report
}

main "$@"
