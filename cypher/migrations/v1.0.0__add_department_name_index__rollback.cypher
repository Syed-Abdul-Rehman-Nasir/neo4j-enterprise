// rollback v1.0.0 — drop Department.name range index
DROP INDEX idx_dept_name IF EXISTS;
DROP INDEX department_name_range IF EXISTS;
