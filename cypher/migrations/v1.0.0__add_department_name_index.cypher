// v1.0.0 — Add Department.name range index for Q1 performance
// (Also present in 00_constraints_indexes.cypher as idx_dept_name; IF NOT EXISTS is idempotent.)
CREATE RANGE INDEX idx_dept_name IF NOT EXISTS
FOR (d:Department) ON (d.name);
