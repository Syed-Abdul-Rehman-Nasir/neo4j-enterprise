#!/usr/bin/env python3
"""Cypher file validator for CI. No external dependencies — stdlib only."""

import sys
import re
from pathlib import Path

ERRORS = []
WARNINGS = []

CYPHER_KEYWORDS = re.compile(
    r'\b(MATCH|CREATE|MERGE|RETURN|WITH|WHERE|CALL|UNWIND|DROP|SHOW|GRANT|FOREACH)\b',
    re.IGNORECASE
)
PARAM_PATTERN = re.compile(r'\$[a-zA-Z_][a-zA-Z0-9_]*')


def validate_file(path: Path) -> list:
    errors = []
    try:
        text = path.read_text(encoding="utf-8")
    except Exception as e:
        errors.append(f"{path}: cannot read file — {e}")
        return errors

    # Strip comment lines
    non_comment = "\n".join(
        line for line in text.splitlines()
        if line.strip() and not line.strip().startswith("//")
    )

    if not non_comment.strip():
        errors.append(f"{path}: file is empty or contains only comments")
        return errors

    # Must contain at least one Cypher keyword
    if not CYPHER_KEYWORDS.search(text):
        errors.append(f"{path}: no Cypher keywords found (MATCH/CREATE/MERGE/RETURN etc.)")

    # Balanced parentheses (ignore // comment lines — docs often use "1)" lists)
    if non_comment.count("(") != non_comment.count(")"):
        errors.append(
            f"{path}: unbalanced parentheses "
            f"({non_comment.count('(')} open vs {non_comment.count(')')} close)"
        )

    # Balanced curly braces
    if non_comment.count("{") != non_comment.count("}"):
        errors.append(
            f"{path}: unbalanced curly braces "
            f"({non_comment.count('{')} open vs {non_comment.count('}')} close)"
        )

    # Warn if query files have no parameters
    if path.parent.name == "queries" and not PARAM_PATTERN.search(text):
        WARNINGS.append(f"WARN  {path}: query file has no $parameters")

    return errors


def main():
    cypher_dir = Path("cypher")
    if not cypher_dir.exists():
        print("ERROR: cypher/ directory not found")
        sys.exit(1)

    files = sorted(cypher_dir.rglob("*.cypher"))
    if not files:
        print("ERROR: no .cypher files found under cypher/")
        sys.exit(1)

    print(f"Validating {len(files)} Cypher files...")

    for f in files:
        file_errors = validate_file(f)
        ERRORS.extend(file_errors)

    for w in WARNINGS:
        print(w)
    for e in ERRORS:
        print(f"ERROR {e}")

    print(f"\nResult: {len(files)} files checked — {len(ERRORS)} errors, {len(WARNINGS)} warnings")

    sys.exit(1 if ERRORS else 0)


if __name__ == "__main__":
    main()
