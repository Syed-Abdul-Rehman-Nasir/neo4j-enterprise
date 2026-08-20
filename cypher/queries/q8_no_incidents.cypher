// =============================================================================
// q8_no_incidents.cypher
// =============================================================================
// WHAT: Find applications that have never had any incident (no inbound AFFECTS).
//
// WHY WHERE NOT (pattern) INSTEAD OF OPTIONAL MATCH + IS NULL:
//   WHERE NOT (a)<-[:AFFECTS]-(:Incident) states anti-join intent directly:
//   "keep applications for which this pattern does not exist." It is more
//   readable and typically more efficient in Neo4j than OPTIONAL MATCH, which
//   builds a row for every application (padding with null when no incident),
//   then filters WHERE i IS NULL. The NOT-pattern form can stop at the first
//   matching incident (existence check) without materializing null joins.
//
// INDEXES USED:
//   - Application.applicationId uniqueness
//   - Application.tier range index (ORDER BY tier)
//
// EXPECTED RESULT SHAPE:
//   | application_name | applicationId | owner | tier |
//   Ordered by tier ASC, name ASC.
//   Sample: HRConnect (APP-003, tier 2), AlertManager (APP-005, tier 3).
// =============================================================================

// --- PRODUCTION (preferred: WHERE NOT pattern) ------------------------------

MATCH (a:Application)
WHERE NOT (a)<-[:AFFECTS]-(:Incident)
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- TEST (hardcoded; same query, no parameters) ----------------------------

MATCH (a:Application)
WHERE NOT (a)<-[:AFFECTS]-(:Incident)
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- VARIANT: OPTIONAL MATCH + WHERE i IS NULL — PRODUCTION -----------------

MATCH (a:Application)
OPTIONAL MATCH (a)<-[:AFFECTS]-(i:Incident)
WITH a, i
WHERE i IS NULL
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- VARIANT: OPTIONAL MATCH + WHERE i IS NULL — TEST -----------------------

MATCH (a:Application)
OPTIONAL MATCH (a)<-[:AFFECTS]-(i:Incident)
WITH a, i
WHERE i IS NULL
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.owner AS owner,
       a.tier AS tier
ORDER BY a.tier ASC, a.name ASC;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (a:Application)
// WHERE NOT (a)<-[:AFFECTS]-(:Incident)
// RETURN a.name, a.applicationId, a.owner, a.tier
// ORDER BY a.tier ASC, a.name ASC;
//
// Expected plan shape (NOT pattern):
//   - NodeByLabelScan(:Application)
//   - AntiSemiApply / LetAntiSemiApply (or similar anti-join) testing AFFECTS
//   - Sort by tier, name
//
// OPTIONAL MATCH variant typically shows OptionalExpand + Filter(i IS NULL),
// which materializes more intermediate rows.
