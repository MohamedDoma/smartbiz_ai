#!/usr/bin/env python3
"""Fail CI when tracked files contain likely secrets or sensitive filenames.

The scanner reports only file paths, line numbers, and key types. It never prints
secret values. Test-only values in CI/example files are intentionally allowlisted.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [ROOT / item.decode() for item in result.stdout.split(b"\0") if item]


ALLOWED_ENV_FILES = {
    "backend/.env.example",
    "backend/.env.testing.example",
    "backend/.env.production.example",
}

SENSITIVE_FILENAME = re.compile(
    r"(^|/)(?:\.env(?:\..+)?|id_rsa|id_ed25519)$|"
    r"\.(?:pem|key|p12|pfx|jks|keystore)$|"
    r"(?:service[-_]?account|credentials|auth)\.json$",
    re.IGNORECASE,
)

TOKEN_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "OpenAI token": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"),
    "Anthropic token": re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}\b"),
    "Stripe secret": re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]{12,}\b"),
    "Stripe webhook secret": re.compile(r"\bwhsec_[A-Za-z0-9]{12,}\b"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{25,}\b"),
}

SENSITIVE_KEYS = {
    "APP_KEY",
    "DB_PASSWORD",
    "POSTGRES_PASSWORD",
    "REDIS_PASSWORD",
    "MAIL_PASSWORD",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "STRIPE_SECRET",
    "STRIPE_WEBHOOK_SECRET",
    "RESEND_API_KEY",
    "AWS_SECRET_ACCESS_KEY",
    "GOOGLE_CLIENT_SECRET",
}

ASSIGNMENT = re.compile(
    r"^\s*(?:-\s*)?([A-Z][A-Z0-9_]+)\s*(?:=|:)\s*([^#\n]*)"
)

TEST_CONTEXT_FILES = {
    ".github/workflows/ci.yml",
    "backend/.env.testing.example",
    "backend/scripts/prepare-test-database.sh",
    "infra/docker-compose.yml",
}

SAFE_TEST_VALUES = {
    "smartbiz_ci",
    "smartbiz_dev",
    "testing",
}


def is_placeholder(value: str) -> bool:
    normalized = value.strip().strip('"\'').lower()
    return (
        normalized in {"", "null", "none", "false", "true"}
        or normalized.startswith("${")
        or normalized.startswith("<")
        or "your_" in normalized
        or "example" in normalized
        or "redacted" in normalized
        or normalized in SAFE_TEST_VALUES
        or normalized.startswith("base64:c21hcnRiaXot")  # deterministic SmartBiz test key
    )


def main() -> int:
    findings: list[str] = []

    for path in tracked_files():
        relative = path.relative_to(ROOT).as_posix()

        if SENSITIVE_FILENAME.search(relative) and relative not in ALLOWED_ENV_FILES:
            findings.append(f"{relative}: sensitive filename is tracked")

        if not path.is_file() or path.stat().st_size > 2_000_000:
            continue

        raw = path.read_bytes()
        if b"\0" in raw:
            continue

        text = raw.decode("utf-8", errors="ignore")
        for number, line in enumerate(text.splitlines(), start=1):
            for label, pattern in TOKEN_PATTERNS.items():
                if pattern.search(line):
                    findings.append(f"{relative}:{number}: possible {label}")

            match = ASSIGNMENT.match(line)
            if not match or match.group(1) not in SENSITIVE_KEYS:
                continue

            key, value = match.groups()
            if is_placeholder(value):
                continue

            if relative in TEST_CONTEXT_FILES:
                continue

            findings.append(f"{relative}:{number}: populated {key}")

    if findings:
        print("Secret scan failed. Values are intentionally not displayed:", file=sys.stderr)
        for finding in sorted(set(findings)):
            print(f"- {finding}", file=sys.stderr)
        return 1

    print("Tracked secret scan passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
