# Migration log

Track applied schema migrations for the Enterprise IT dependency graph.

## Naming convention

```
Rollback file naming convention:
  Forward:  v{MAJOR}.{MINOR}.{PATCH}__{description}.cypher
  Rollback: v{MAJOR}.{MINOR}.{PATCH}__{description}__rollback.cypher

The deploy workflow extracts the version prefix (vX.Y.Z) from the applied
migration filename and uses a glob to find the matching rollback file.
This means the description portion can change without breaking rollback resolution.
```

## Applied migrations

| Version | File | Description | Rollback |
|---|---|---|---|
| v1.0.0 | `v1.0.0__add_department_name_index.cypher` | Add `idx_dept_name` range index on `Department.name` | `v1.0.0__add_department_name_index__rollback.cypher` |
