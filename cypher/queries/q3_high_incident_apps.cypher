// =============================================================================
// q3_high_incident_apps.cypher
// =============================================================================
// WHAT: Find applications with more than $minIncidents related incidents,
//       sorted by incident count descending. Includes titles and severities.
//
// WHY WRITTEN THIS WAY:
//   Aggregation happens in WITH first; the threshold filter is applied AFTER
//   aggregation with WHERE. Filtering with WHERE before WITH/count would drop
//   rows before they are counted (wrong semantics for "apps with > N incidents").
//
// INDEXES USED:
//   - Application.applicationId uniqueness
//   - Incident.severity / Incident.status range indexes (available when filtering
//     incidents further); composite Incident(severity, status) for troubleshooting
//   - AFFECTS relationship expand from Application or Incident
//
// EXPECTED RESULT SHAPE (main query):
//   | application_name | applicationId | tier | incident_count |
//   | incident_titles (list) | severities (list) |
//   Sample ($minIncidents = 3): only FinanceSuite (APP-001) with 6 incidents.
//
// SEVERITY VARIANT RESULT SHAPE:
//   Same identity columns plus p1_count, p2_count, p3_count.
// =============================================================================

// --- PRODUCTION (parameters) -------------------------------------------------
// :param minIncidents => 3

MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
WITH a,
     count(i) AS incident_count,
     collect(i.title) AS incident_titles,
     collect(i.severity) AS severities
WHERE incident_count > $minIncidents
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       incident_count,
       incident_titles,
       severities
ORDER BY incident_count DESC;

// --- TEST (hardcoded; run immediately) --------------------------------------

MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
WITH a,
     count(i) AS incident_count,
     collect(i.title) AS incident_titles,
     collect(i.severity) AS severities
WHERE incident_count > 3
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       incident_count,
       incident_titles,
       severities
ORDER BY incident_count DESC;

// --- VARIANT: severity breakdown (P1 / P2 / P3) — PRODUCTION ----------------

MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
WITH a,
     count(i) AS incident_count,
     collect(i.title) AS incident_titles,
     sum(CASE WHEN i.severity = 'P1' THEN 1 ELSE 0 END) AS p1_count,
     sum(CASE WHEN i.severity = 'P2' THEN 1 ELSE 0 END) AS p2_count,
     sum(CASE WHEN i.severity = 'P3' THEN 1 ELSE 0 END) AS p3_count
WHERE incident_count > $minIncidents
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       incident_count,
       incident_titles,
       p1_count,
       p2_count,
       p3_count
ORDER BY incident_count DESC;

// --- VARIANT: severity breakdown — TEST -------------------------------------

MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
WITH a,
     count(i) AS incident_count,
     collect(i.title) AS incident_titles,
     sum(CASE WHEN i.severity = 'P1' THEN 1 ELSE 0 END) AS p1_count,
     sum(CASE WHEN i.severity = 'P2' THEN 1 ELSE 0 END) AS p2_count,
     sum(CASE WHEN i.severity = 'P3' THEN 1 ELSE 0 END) AS p3_count
WHERE incident_count > 3
RETURN a.name AS application_name,
       a.applicationId AS applicationId,
       a.tier AS tier,
       incident_count,
       incident_titles,
       p1_count,
       p2_count,
       p3_count
ORDER BY incident_count DESC;

// --- EXPLAIN ----------------------------------------------------------------
// EXPLAIN
// MATCH (a:Application)<-[:AFFECTS]-(i:Incident)
// WITH a, count(i) AS incident_count, collect(i.title) AS incident_titles, collect(i.severity) AS severities
// WHERE incident_count > $minIncidents
// RETURN a.name, a.applicationId, a.tier, incident_count, incident_titles, severities
// ORDER BY incident_count DESC;
//
// Expected plan shape:
//   - NodeByLabelScan(:Application) or AllNodesScan + Filter
//   - Expand(Incoming) AFFECTS → Incident
//   - EagerAggregation (count / collect)
//   - Filter (incident_count > $minIncidents)   ← after aggregation
//   - Sort
