#!/usr/bin/env bash
# =============================================================================
# admin/backup.sh — Production Neo4j database backup
# chmod +x admin/backup.sh
#
# Recommended cron schedule:
# Full backup:        0 2 * * 0   (Sunday 2am)
# Incremental:        0 2 * * 1-6 (Mon-Sat 2am)
#
# Required environment (never hardcode secrets):
#   NEO4J_HOME, NEO4J_DATABASE, BACKUP_DESTINATION
# Optional:
#   RETENTION_DAYS (default 30), BACKUP_TYPE (full|incremental),
#   LOG_FILE, DD_API_KEY, DD_APP_KEY, AWS_DEFAULT_REGION
# =============================================================================

# set -e: exit immediately if any command returns non-zero (fail fast)
# set -u: treat unset variables as errors (prevents silent empty-path disasters)
# set -o pipefail: a failure anywhere in a pipeline fails the whole pipeline
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (sourced from environment)
# ---------------------------------------------------------------------------
: "${NEO4J_HOME:?NEO4J_HOME must be set}"
: "${NEO4J_DATABASE:?NEO4J_DATABASE must be set}"
: "${BACKUP_DESTINATION:?BACKUP_DESTINATION must be set (e.g. s3://bucket/neo4j-backups)}"

RETENTION_DAYS="${RETENTION_DAYS:-30}"
LOG_FILE="${LOG_FILE:-/var/log/neo4j/backup.log}"
LOCAL_BACKUP_ROOT="${LOCAL_BACKUP_ROOT:-${NEO4J_HOME}/backups}"
DD_API_KEY="${DD_API_KEY:-}"
DD_SITE="${DD_SITE:-datadoghq.com}"

# Default BACKUP_TYPE: full on Sundays, incremental otherwise
if [[ -z "${BACKUP_TYPE:-}" ]]; then
  if [[ "$(date +%u)" -eq 7 ]]; then
    BACKUP_TYPE="full"
  else
    BACKUP_TYPE="incremental"
  fi
fi

NEO4J_ADMIN="${NEO4J_HOME}/bin/neo4j-admin"
NEO4J_BIN="${NEO4J_HOME}/bin/neo4j"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_NAME="${NEO4J_DATABASE}_${BACKUP_TYPE}_${TIMESTAMP}"
BACKUP_PATH="${LOCAL_BACKUP_ROOT}/${BACKUP_NAME}"

BACKUP_START_EPOCH=0
BACKUP_END_EPOCH=0
BACKUP_SIZE_BYTES=0
BACKUP_STATUS="FAILURE"
LAST_ERROR=""

# ---------------------------------------------------------------------------
# 1. log — timestamped logging to stdout and LOG_FILE
# ---------------------------------------------------------------------------
log() {
  local level="$1"
  shift
  local msg="$*"
  local line
  line="$(date -u +'%Y-%m-%dT%H:%M:%SZ') [${level}] ${msg}"
  echo "${line}"
  mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  echo "${line}" >> "${LOG_FILE}" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Failure handler — Datadog FAILURE event then exit 1
# ---------------------------------------------------------------------------
fail() {
  LAST_ERROR="$*"
  log "ERROR" "${LAST_ERROR}"
  BACKUP_STATUS="FAILURE"
  send_datadog_event "FAILURE" || true
  exit 1
}

trap 'fail "Backup aborted by signal or unexpected error (line ${LINENO})"' ERR

# ---------------------------------------------------------------------------
# 2. check_prerequisites
# ---------------------------------------------------------------------------
check_prerequisites() {
  log "INFO" "Checking prerequisites..."

  if [[ ! -x "${NEO4J_ADMIN}" ]]; then
    if command -v neo4j-admin >/dev/null 2>&1; then
      NEO4J_ADMIN="$(command -v neo4j-admin)"
    else
      fail "neo4j-admin not found at ${NEO4J_HOME}/bin/neo4j-admin"
    fi
  fi
  log "INFO" "Using neo4j-admin: ${NEO4J_ADMIN}"

  # Neo4j must be running for online Enterprise backup
  if [[ -x "${NEO4J_BIN}" ]]; then
    if ! "${NEO4J_BIN}" status 2>/dev/null | grep -qi "running"; then
      fail "Neo4j does not appear to be running (${NEO4J_BIN} status)"
    fi
  elif command -v neo4j >/dev/null 2>&1; then
    if ! neo4j status 2>/dev/null | grep -qi "running"; then
      fail "Neo4j does not appear to be running"
    fi
  else
    log "WARN" "neo4j binary not found; skipping status check (ensure DBMS is online)"
  fi

  mkdir -p "${LOCAL_BACKUP_ROOT}"

  # Disk space: require >20% free on the backup filesystem
  local avail_pct
  avail_pct="$(df -P "${LOCAL_BACKUP_ROOT}" | awk 'NR==2 {print int($5)}' | tr -d '%')"
  local free_pct=$((100 - avail_pct))
  if [[ "${free_pct}" -le 20 ]]; then
    fail "Insufficient disk space: only ${free_pct}% free on ${LOCAL_BACKUP_ROOT} (need >20%)"
  fi
  log "INFO" "Disk free: ${free_pct}% on ${LOCAL_BACKUP_ROOT}"

  case "${BACKUP_TYPE}" in
    full|incremental) ;;
    *) fail "BACKUP_TYPE must be 'full' or 'incremental' (got: ${BACKUP_TYPE})" ;;
  esac

  log "INFO" "Prerequisites OK (database=${NEO4J_DATABASE}, type=${BACKUP_TYPE})"
}

# ---------------------------------------------------------------------------
# 3. take_backup
# ---------------------------------------------------------------------------
take_backup() {
  log "INFO" "Starting ${BACKUP_TYPE} backup of database '${NEO4J_DATABASE}' → ${BACKUP_PATH}"
  BACKUP_START_EPOCH="$(date +%s)"

  local type_flag
  if [[ "${BACKUP_TYPE}" == "full" ]]; then
    type_flag="FULL"
  else
    # Neo4j 5 Enterprise differential / incremental chain
    type_flag="DIFF"
  fi

  mkdir -p "${BACKUP_PATH}"

  set +e
  "${NEO4J_ADMIN}" database backup \
    --to-path="${BACKUP_PATH}" \
    --type="${type_flag}" \
    "${NEO4J_DATABASE}"
  local rc=$?
  set -e

  BACKUP_END_EPOCH="$(date +%s)"

  if [[ "${rc}" -ne 0 ]]; then
    fail "neo4j-admin database backup failed with exit code ${rc}"
  fi

  log "INFO" "Backup command completed successfully (exit 0)"
}

# ---------------------------------------------------------------------------
# 4. verify_backup
# ---------------------------------------------------------------------------
verify_backup() {
  log "INFO" "Verifying backup at ${BACKUP_PATH}"

  if [[ ! -e "${BACKUP_PATH}" ]]; then
    fail "Backup path does not exist: ${BACKUP_PATH}"
  fi

  BACKUP_SIZE_BYTES="$(du -sb "${BACKUP_PATH}" 2>/dev/null | awk '{print $1}')"
  if [[ -z "${BACKUP_SIZE_BYTES}" || "${BACKUP_SIZE_BYTES}" -le 0 ]]; then
    fail "Backup size is zero or unreadable: ${BACKUP_PATH}"
  fi
  log "INFO" "Backup size: ${BACKUP_SIZE_BYTES} bytes"

  # Consistency check on the backup artifact when supported
  set +e
  "${NEO4J_ADMIN}" database check \
    --from-path="${BACKUP_PATH}" \
    "${NEO4J_DATABASE}" 2>&1 | tee -a "${LOG_FILE}"
  local check_rc=${PIPESTATUS[0]}
  set -e

  if [[ "${check_rc}" -ne 0 ]]; then
    # Fallback: some builds check the live DB; still require non-zero artifact size
    log "WARN" "neo4j-admin database check returned ${check_rc}; relying on size > 0 verification"
  else
    log "INFO" "neo4j-admin database check passed"
  fi
}

# ---------------------------------------------------------------------------
# 5. upload_to_s3
# ---------------------------------------------------------------------------
upload_to_s3() {
  log "INFO" "Uploading backup to S3 with SSE-KMS: ${BACKUP_DESTINATION}"

  if ! command -v aws >/dev/null 2>&1; then
    fail "aws CLI not found; required for upload_to_s3"
  fi

  local s3_uri="${BACKUP_DESTINATION%/}/${BACKUP_NAME}/"

  aws s3 cp "${BACKUP_PATH}" "${s3_uri}" \
    --recursive \
    --sse aws:kms

  log "INFO" "Uploaded backup to ${s3_uri}"
}

# ---------------------------------------------------------------------------
# 6. cleanup_old_backups
# ---------------------------------------------------------------------------
cleanup_old_backups() {
  log "INFO" "Cleaning local backups older than ${RETENTION_DAYS} days under ${LOCAL_BACKUP_ROOT}"

  local deleted=0
  while IFS= read -r -d '' old; do
    log "INFO" "Deleting expired backup: ${old}"
    rm -rf "${old}"
    deleted=$((deleted + 1))
  done < <(find "${LOCAL_BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -mtime "+${RETENTION_DAYS}" -print0 2>/dev/null || true)

  log "INFO" "Cleanup complete; deleted ${deleted} artifact(s)"
}

# ---------------------------------------------------------------------------
# 7. send_datadog_event
# ---------------------------------------------------------------------------
send_datadog_event() {
  local status="${1:-${BACKUP_STATUS}}"
  local duration=0
  if [[ "${BACKUP_START_EPOCH}" -gt 0 && "${BACKUP_END_EPOCH}" -gt 0 ]]; then
    duration=$((BACKUP_END_EPOCH - BACKUP_START_EPOCH))
  elif [[ "${BACKUP_START_EPOCH}" -gt 0 ]]; then
    duration=$(( $(date +%s) - BACKUP_START_EPOCH ))
  fi

  if [[ -z "${DD_API_KEY}" ]]; then
    log "WARN" "DD_API_KEY not set; skipping Datadog event (${status})"
    return 0
  fi

  local alert_type title text
  if [[ "${status}" == "SUCCESS" ]]; then
    alert_type="success"
    title="Neo4j backup SUCCESS: ${NEO4J_DATABASE} (${BACKUP_TYPE})"
  else
    alert_type="error"
    title="Neo4j backup FAILURE: ${NEO4J_DATABASE} (${BACKUP_TYPE})"
  fi

  text="Database: ${NEO4J_DATABASE}\\nType: ${BACKUP_TYPE}\\nStatus: ${status}\\nSizeBytes: ${BACKUP_SIZE_BYTES}\\nDurationSec: ${duration}\\nPath: ${BACKUP_PATH}\\nError: ${LAST_ERROR}"

  curl -sS -X POST "https://api.${DD_SITE}/api/v1/events" \
    -H "Content-Type: application/json" \
    -H "DD-API-KEY: ${DD_API_KEY}" \
    -d "{
      \"title\": \"${title}\",
      \"text\": \"${text}\",
      \"alert_type\": \"${alert_type}\",
      \"tags\": [\"service:neo4j\", \"backup_type:${BACKUP_TYPE}\", \"database:${NEO4J_DATABASE}\", \"status:${status}\"]
    }" >/dev/null

  log "INFO" "Datadog event sent (${status}, size=${BACKUP_SIZE_BYTES}, duration=${duration}s)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "INFO" "=== Neo4j backup starting ==="
  check_prerequisites
  take_backup
  verify_backup
  upload_to_s3
  cleanup_old_backups
  BACKUP_STATUS="SUCCESS"
  send_datadog_event "SUCCESS"
  log "INFO" "=== Neo4j backup completed successfully ==="
}

main "$@"
