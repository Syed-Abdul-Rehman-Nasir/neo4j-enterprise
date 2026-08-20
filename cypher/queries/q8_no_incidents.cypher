// =============================================================================
// q8_no_incidents.cypher
// =============================================================================
// WHAT: Find applications with no inbound AFFECTS from incidents at or before
//       $asOf (historical "clean" apps as of a point in time).
//
// PARAMETERS:
//   $asOf — optional datetime (or null). When null, any incident counts as
//           "has incident". When set, only incidents with i.ts <= $asOf count.
//
// VARIANTS:
//   1) NOT EXISTS subquery (preferred) — production block below
//   2) OPTIONAL MATCH + count = 0 — alternative below
//
// INDEXES USED:
//   - Application.applicationId uniqueness
//   - Application.tier range index (ORDER BY tier)
//   - Incident.ts range index (cutoff filter)
//
// EXPECTED RESULT SHAPE:
//   | application | id | owner | tier |
//   Sample ($asOf far future / null on sample): HRConnect (APP-003), AlertManager (APP-005).
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param asOf => null   OR   :param asOf => datetime('2099-12-31T23:59:59')

MATCH (a:Application)
WHERE NOT EXISTS {
  MATCH (i:Incident)-[:AFFECTS]->(a)
  WHERE $asOf IS NULL OR i.ts <= datetime($asOf)
}
RETURN a.name AS application,
       a.applicationId AS id,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- TEST (hardcoded far-future cutoff; run immediately) --------------------

MATCH (a:Application)
WHERE NOT EXISTS {
  MATCH (i:Incident)-[:AFFECTS]->(a)
  WHERE i.ts <= datetime('2099-12-31T23:59:59')
}
RETURN a.name AS application,
       a.applicationId AS id,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- VARIANT: OPTIONAL MATCH + count = 0 — PRODUCTION ----------------------

MATCH (a:Application)
OPTIONAL MATCH (i:Incident)-[:AFFECTS]->(a)
WHERE $asOf IS NULL OR i.ts <= datetime($asOf)
WITH a, count(i) AS incidentHits
WHERE incidentHits = 0
RETURN a.name AS application,
       a.applicationId AS id,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- VARIANT: OPTIONAL MATCH + count = 0 — TEST -----------------------------

MATCH (a:Application)
OPTIONAL MATCH (i:Incident)-[:AFFECTS]->(a)
WHERE i.ts <= datetime('2099-12-31T23:59:59')
WITH a, count(i) AS incidentHits
WHERE incidentHits = 0
RETURN a.name AS application,
       a.applicationId AS id,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;
