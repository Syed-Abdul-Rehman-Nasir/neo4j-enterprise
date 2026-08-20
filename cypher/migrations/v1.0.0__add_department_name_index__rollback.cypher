// rollback v1.0.0 — drop Department.name range index
DROP INDEX department_name_range IF EXISTS;
