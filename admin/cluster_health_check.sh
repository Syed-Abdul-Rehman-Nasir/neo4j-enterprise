#!/usr/bin/env bash
# =============================================================================
# admin/cluster_health_check.sh
# Cluster / instance health probe for Kubernetes readiness or cron monitors.
# chmod +x admin/cluster_health_check.sh
#
# Environment:
#   NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD
#   NEO4J_HOME (optional; used to locate cypher-shell)
#   NEO4J_DATABASE (optional; default neo4j for index checks)
# =============================================================================

set -euo pipefail

FORMAT="text"
EXPECTED_ROLE=""
MIN_MEMBERS=3
STRICT=0

NEO4J_URI="${NEO4J_URI:-bolt://localhost:7687}"
NEO4J_USERNAME="${NEO4J_USERNAME:-neo4j}"
NEO4J_PASSWORD="${NEO4J_PASSWORD:-}"
NEO4J_DATABASE="${NEO4J_DATABASE:-neo4j}"
NEO4J_HOME="${NEO4J_HOME:-}"

# Severity tracking: 0=PASS, 1=WARN, 2=FAIL
WORST=0
declare -a CHECK_NAMES=()
declare -a CHECK_RESULTS=()
declare -a CHECK_DETAILS=()

usage() {
  cat <<'EOF'
Usage: cluster_health_check.sh [OPTIONS]

Options:
  --format json|text     Output format (default: text)
  --expected-role ROLE   PRIMARY | SECONDARY | READ_REPLICA (required for role check)
  --min-members N        Minimum cluster members / quorum (default: 3)
  --strict               Treat WARN as FAIL (exit 1 instead of 2)
  --help                 Show this help

Exit codes:
  0  All checks PASS
  1  Any check FAIL (or WARN when --strict)
  2  Any WARN and no FAIL (non-strict)

Checks and thresholds:
  1. bolt_connectivity
       cypher-shell "RETURN 1" with 5s timeout.
       PASS/FAIL with latency in ms. FAIL if unreachable or timeout.

  2. cluster_role
       CALL dbms.cluster.role() compared to --expected-role.
       FAIL if role does not match expected.

  3. cluster_members
       CALL dbms.cluster.overview() — count total, primaries, secondaries.
       FAIL if total members < --min-members (default 3).

  4. database_status
       SHOW DATABASES where currentStatus <> 'online'.
       FAIL if any database is not online (prints statusMessage).

  5. replication_lag
       CALL dbms.cluster.protocols() — lag in ms.
       WARN if lag > 5000ms; FAIL if lag > 30000ms.

  6. index_health
       SHOW INDEXES where state <> 'ONLINE'.
       FAIL if any index is FAILED; WARN if any is POPULATING.

  7. page_cache_ratio
       JMX page cache hit ratio.
       WARN if < 95%; FAIL if < 80%.

Environment: NEO4J_URI, NEO4J_USERNAME, NEO4J_PASSWORD, NEO4J_HOME, NEO4J_DATABASE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --expected-role)
      EXPECTED_ROLE="${2:-}"
      shift 2
      ;;
    --min-members)
      MIN_MEMBERS="${2:-3}"
      shift 2
      ;;
    --strict)
      STRICT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${FORMAT}" != "json" && "${FORMAT}" != "text" ]]; then
  echo "Invalid --format: ${FORMAT}" >&2
  exit 1
fi

resolve_cypher_shell() {
  if [[ -n "${NEO4J_HOME}" && -x "${NEO4J_HOME}/bin/cypher-shell" ]]; then
    echo "${NEO4J_HOME}/bin/cypher-shell"
  elif command -v cypher-shell >/dev/null 2>&1; then
    command -v cypher-shell
  else
    echo ""
  fi
}

CYPHER_SHELL="$(resolve_cypher_shell)"

record_result() {
  local name="$1"
  local result="$2"  # PASS|WARN|FAIL
  local detail="$3"
  CHECK_NAMES+=("${name}")
  CHECK_RESULTS+=("${result}")
  CHECK_DETAILS+=("${detail}")
  case "${result}" in
    FAIL) WORST=2 ;;
    WARN) [[ "${WORST}" -lt 1 ]] && WORST=1 ;;
  esac
}

# Run Cypher; print stdout only. Returns non-zero on failure without aborting caller.
run_cypher() {
  local database="${1:-system}"
  shift
  local query="$*"
  if [[ -z "${CYPHER_SHELL}" ]]; then
    echo "cypher-shell not found"
    return 1
  fi
  if [[ -z "${NEO4J_PASSWORD}" ]]; then
    echo "NEO4J_PASSWORD not set"
    return 1
  fi
  set +e
  local out
  out="$("${CYPHER_SHELL}" -a "${NEO4J_URI}" -u "${NEO4J_USERNAME}" -p "${NEO4J_PASSWORD}" \
    -d "${database}" --format plain "${query}" 2>&1)"
  local rc=$?
  set -e
  echo "${out}"
  return "${rc}"
}

# ---------------------------------------------------------------------------
# 1. bolt_connectivity
# ---------------------------------------------------------------------------
bolt_connectivity() {
  local name="bolt_connectivity"
  if [[ -z "${CYPHER_SHELL}" ]]; then
    record_result "${name}" "FAIL" "cypher-shell not found"
    return
  fi
  if [[ -z "${NEO4J_PASSWORD}" ]]; then
    record_result "${name}" "FAIL" "NEO4J_PASSWORD not set"
    return
  fi

  local start_ns end_ns latency_ms out rc
  start_ns="$(date +%s%N 2>/dev/null || echo 0)"

  set +e
  if command -v timeout >/dev/null 2>&1; then
    out="$(timeout 5s "${CYPHER_SHELL}" -a "${NEO4J_URI}" -u "${NEO4J_USERNAME}" -p "${NEO4J_PASSWORD}" \
      --format plain "RETURN 1 AS ok;" 2>&1)"
    rc=$?
  else
    out="$("${CYPHER_SHELL}" -a "${NEO4J_URI}" -u "${NEO4J_USERNAME}" -p "${NEO4J_PASSWORD}" \
      --format plain "RETURN 1 AS ok;" 2>&1)"
    rc=$?
  fi
  set -e

  end_ns="$(date +%s%N 2>/dev/null || echo 0)"
  if [[ "${start_ns}" != "0" && "${end_ns}" != "0" ]]; then
    latency_ms=$(( (end_ns - start_ns) / 1000000 ))
  else
    latency_ms=-1
  fi

  if [[ "${rc}" -eq 0 ]] && echo "${out}" | grep -q "1"; then
    record_result "${name}" "PASS" "latency_ms=${latency_ms}"
  elif [[ "${rc}" -eq 124 ]]; then
    record_result "${name}" "FAIL" "timeout after 5s; latency_ms=${latency_ms}"
  else
    record_result "${name}" "FAIL" "bolt unreachable (rc=${rc}); latency_ms=${latency_ms}; ${out}"
  fi
}

# ---------------------------------------------------------------------------
# 2. cluster_role
# ---------------------------------------------------------------------------
cluster_role() {
  local name="cluster_role"
  local out rc role
  set +e
  out="$(run_cypher system "CALL dbms.cluster.role() YIELD role RETURN role;")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    record_result "${name}" "FAIL" "unable to read cluster role (single-instance or no permission?): ${out}"
    return
  fi

  role="$(echo "${out}" | awk 'NF && $1 !~ /role/ {print toupper($1); exit}')"
  if [[ -z "${role}" ]]; then
    role="$(echo "${out}" | tr -d '\r' | awk 'NF{print toupper($NF)}' | tail -n 1)"
  fi

  if [[ -z "${EXPECTED_ROLE}" ]]; then
    record_result "${name}" "PASS" "Current role: ${role:-unknown} (no expected role specified)"
    return
  fi

  local expected
  expected="$(echo "${EXPECTED_ROLE}" | tr '[:lower:]' '[:upper:]')"

  if [[ "${role}" == "${expected}" ]]; then
    record_result "${name}" "PASS" "current=${role}; expected=${expected}"
  else
    record_result "${name}" "FAIL" "current=${role:-unknown}; expected=${expected}"
  fi
}

# ---------------------------------------------------------------------------
# 3. cluster_members
# ---------------------------------------------------------------------------
cluster_members() {
  local name="cluster_members"
  local out rc
  set +e
  out="$(run_cypher system "CALL dbms.cluster.overview() YIELD id, role RETURN id, role;")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    record_result "${name}" "FAIL" "unable to read cluster overview: ${out}"
    return
  fi

  local total=0 primaries=0 secondaries=0 replicas=0
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    echo "${line}" | grep -qi "role\|id" && continue
    total=$((total + 1))
    local upper
    upper="$(echo "${line}" | tr '[:lower:]' '[:upper:]')"
    if echo "${upper}" | grep -q "PRIMARY\|LEADER\|FOLLOWER"; then
      # Treat LEADER/FOLLOWER as primary-group members for Causal Cluster naming
      if echo "${upper}" | grep -q "SECONDARY\|READ_REPLICA\|REPLICA"; then
        :
      else
        primaries=$((primaries + 1))
      fi
    fi
    if echo "${upper}" | grep -q "SECONDARY"; then
      secondaries=$((secondaries + 1))
    fi
    if echo "${upper}" | grep -q "READ_REPLICA\|REPLICA"; then
      replicas=$((replicas + 1))
    fi
  done <<< "${out}"

  # Fallback count: non-empty data lines
  if [[ "${total}" -eq 0 ]]; then
    total="$(echo "${out}" | awk 'NF && $0 !~ /role/ && $0 !~ /^id/ {c++} END{print c+0}')"
  fi

  local detail="total=${total}; primaries=${primaries}; secondaries=${secondaries}; read_replicas=${replicas}; min_members=${MIN_MEMBERS}"
  if [[ "${total}" -lt "${MIN_MEMBERS}" ]]; then
    record_result "${name}" "FAIL" "${detail}"
  else
    record_result "${name}" "PASS" "${detail}"
  fi
}

# ---------------------------------------------------------------------------
# 4. database_status
# ---------------------------------------------------------------------------
database_status() {
  local name="database_status"
  local out rc
  set +e
  out="$(run_cypher system "SHOW DATABASES YIELD name, currentStatus, statusMessage WHERE currentStatus <> 'online' RETURN name, currentStatus, statusMessage;")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    record_result "${name}" "FAIL" "SHOW DATABASES failed: ${out}"
    return
  fi

  # If only headers or empty → all online
  local bad
  bad="$(echo "${out}" | awk 'NF && $0 !~ /name/ && $0 !~ /currentStatus/ && $0 !~ /statusMessage/ {print}' )"
  if [[ -z "${bad}" ]]; then
    record_result "${name}" "PASS" "all databases online"
  else
    record_result "${name}" "FAIL" "not online: ${bad}"
  fi
}

# ---------------------------------------------------------------------------
# 5. replication_lag
# ---------------------------------------------------------------------------
replication_lag() {
  local name="replication_lag"
  local out rc
  set +e
  # Prefer a lag/milliseconds style field when present in protocols output
  out="$(run_cypher system "CALL dbms.cluster.protocols() YIELD *;")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    record_result "${name}" "FAIL" "unable to read cluster protocols / lag: ${out}"
    return
  fi

  # Extract largest integer that looks like a lag in ms (heuristic for mixed output)
  local lag_ms
  lag_ms="$(echo "${out}" | grep -oE '[0-9]+' | sort -n | tail -n 1)"
  if [[ -z "${lag_ms}" ]]; then
    # No numeric lag exposed — treat as PASS with note if protocols call succeeded
    record_result "${name}" "PASS" "protocols reachable; lag_ms=0 (no lag field reported)"
    return
  fi

  if [[ "${lag_ms}" -gt 30000 ]]; then
    record_result "${name}" "FAIL" "lag_ms=${lag_ms} (>30000)"
  elif [[ "${lag_ms}" -gt 5000 ]]; then
    record_result "${name}" "WARN" "lag_ms=${lag_ms} (>5000)"
  else
    record_result "${name}" "PASS" "lag_ms=${lag_ms}"
  fi
}

# ---------------------------------------------------------------------------
# 6. index_health
# ---------------------------------------------------------------------------
index_health() {
  local name="index_health"
  local out rc
  set +e
  out="$(run_cypher "${NEO4J_DATABASE}" "SHOW INDEXES YIELD name, state WHERE state <> 'ONLINE' RETURN name, state;")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    record_result "${name}" "FAIL" "SHOW INDEXES failed: ${out}"
    return
  fi

  local failed populating other
  failed="$(echo "${out}" | grep -i "FAILED" || true)"
  populating="$(echo "${out}" | grep -i "POPULATING" || true)"
  other="$(echo "${out}" | awk 'NF && $0 !~ /name/ && $0 !~ /state/ && toupper($0) !~ /FAILED/ && toupper($0) !~ /POPULATING/ {print}' || true)"

  if [[ -n "${failed}" ]]; then
    record_result "${name}" "FAIL" "FAILED indexes: ${failed}"
  elif [[ -n "${populating}" ]]; then
    record_result "${name}" "WARN" "POPULATING indexes: ${populating}"
  elif [[ -n "${other}" ]]; then
    record_result "${name}" "WARN" "non-ONLINE indexes: ${other}"
  else
    record_result "${name}" "PASS" "all indexes ONLINE"
  fi
}

# ---------------------------------------------------------------------------
# 7. page_cache_ratio
# ---------------------------------------------------------------------------
page_cache_ratio() {
  local name="page_cache_ratio"
  local out rc
  set +e
  out="$(run_cypher system "CALL dbms.queryJmx('org.neo4j:instance=kernel#0,name=Page cache') YIELD attributes RETURN attributes;")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    # Fallback metric query used in some Neo4j 5 deployments
    set +e
    out="$(run_cypher system "CALL dbms.queryJmx('neo4j.metrics:name=neo4j.database.*.page_cache.hit_ratio') YIELD attributes RETURN attributes;")"
    rc=$?
    set -e
  fi

  if [[ "${rc}" -ne 0 ]]; then
    record_result "${name}" "FAIL" "unable to read page cache JMX: ${out}"
    return
  fi

  # Parse a ratio: either 0.0–1.0 or 0–100
  local ratio_raw ratio_pct
  ratio_raw="$(echo "${out}" | grep -oE '0?\.[0-9]+|[0-9]+\.[0-9]+|[0-9]+' | head -n 1)"
  if [[ -z "${ratio_raw}" ]]; then
    record_result "${name}" "FAIL" "could not parse hit ratio from JMX output"
    return
  fi

  # Convert to percent using awk
  ratio_pct="$(awk -v r="${ratio_raw}" 'BEGIN { if (r <= 1.0) printf "%.2f", r*100; else printf "%.2f", r }')"

  local cmp
  cmp="$(awk -v p="${ratio_pct}" 'BEGIN { if (p+0 < 80) print "fail"; else if (p+0 < 95) print "warn"; else print "pass" }')"

  case "${cmp}" in
    fail) record_result "${name}" "FAIL" "hit_ratio_pct=${ratio_pct} (<80)" ;;
    warn) record_result "${name}" "WARN" "hit_ratio_pct=${ratio_pct} (<95)" ;;
    *)    record_result "${name}" "PASS" "hit_ratio_pct=${ratio_pct}" ;;
  esac
}

# ---------------------------------------------------------------------------
# Output + exit
# ---------------------------------------------------------------------------
emit_output() {
  local overall="PASS"
  local exit_code=0
  if [[ "${WORST}" -eq 2 ]]; then
    overall="FAIL"
    exit_code=1
  elif [[ "${WORST}" -eq 1 ]]; then
    overall="WARN"
    if [[ "${STRICT}" -eq 1 ]]; then
      exit_code=1
      overall="FAIL"
    else
      exit_code=2
    fi
  fi

  if [[ "${FORMAT}" == "json" ]]; then
    echo -n "{"
    echo -n "\"status\":\"${overall}\","
    echo -n "\"exit_code\":${exit_code},"
    echo -n "\"checks\":["
    local i first=1
    for i in "${!CHECK_NAMES[@]}"; do
      [[ "${first}" -eq 1 ]] || echo -n ","
      first=0
      local detail_escaped
      detail_escaped="$(printf '%s' "${CHECK_DETAILS[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"
      echo -n "{\"name\":\"${CHECK_NAMES[$i]}\",\"result\":\"${CHECK_RESULTS[$i]}\",\"detail\":\"${detail_escaped}\"}"
    done
    echo -n "]"
    echo "}"
  else
    echo "=== Neo4j Cluster Health Check ==="
    echo "Overall: ${overall} (exit ${exit_code})"
    echo "----------------------------------"
    local i
    for i in "${!CHECK_NAMES[@]}"; do
      printf "%-20s %-4s %s\n" "${CHECK_NAMES[$i]}" "${CHECK_RESULTS[$i]}" "${CHECK_DETAILS[$i]}"
    done
    echo "----------------------------------"
  fi

  return "${exit_code}"
}

main() {
  bolt_connectivity
  cluster_role
  cluster_members
  database_status
  replication_lag
  index_health
  page_cache_ratio

  set +e
  emit_output
  local ec=$?
  set -e
  exit "${ec}"
}

main "$@"
