// v1.0.0 — Add Department.name range index for Q1 performance
CREATE RANGE INDEX department_name_range IF NOT EXISTS
FOR (d:Department) ON (d.name);
