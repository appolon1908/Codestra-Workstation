#!/usr/bin/env bash
set -euo pipefail

echo "Codestra Codex Cloud workstation bootstrap"
echo "Expected canonical owner: appolon1908"
echo "Expected repository count: 113"

CONTROL_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WORKSPACE_ROOT="$(dirname "$CONTROL_ROOT")"
CATALOG="$CONTROL_ROOT/.codestra/repository-catalog.yaml"
MANIFEST="$CONTROL_ROOT/codex-cloud/environment.yaml"

for cmd in git python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool missing: $cmd" >&2
    exit 1
  fi
done

test -f "$CATALOG" || { echo "ERROR: missing $CATALOG" >&2; exit 1; }
test -f "$MANIFEST" || { echo "ERROR: missing $MANIFEST" >&2; exit 1; }

echo "git: $(git --version)"
echo "python: $(python3 --version 2>&1)"

python3 - "$CATALOG" "$MANIFEST" <<'PY'
import re, sys
catalog, manifest = sys.argv[1], sys.argv[2]
ct = open(catalog, encoding="utf-8").read()
mt = open(manifest, encoding="utf-8").read()
m1 = re.search(r"repository_count:\s*(\d+)", ct)
m2 = re.search(r"repository_count:\s*(\d+)", mt)
if not m1 or not m2:
    raise SystemExit("ERROR: repository_count missing")
if m1.group(1) != m2.group(1):
    raise SystemExit(f"ERROR: catalog/manifest count mismatch: {m1.group(1)} != {m2.group(1)}")
print(f"catalog/manifest repository_count={m1.group(1)}")
PY

mapfile -t GIT_DIRS < <(find "$WORKSPACE_ROOT" -maxdepth 3 -type d -name .git -print 2>/dev/null | sort)
echo "Detected checked-out git repositories: ${#GIT_DIRS[@]}"
if [ "${#GIT_DIRS[@]}" -lt 1 ]; then
  echo "ERROR: no checked-out repositories detected" >&2
  exit 1
fi

echo "Workstation bootstrap complete."
echo "Do not install every repository's dependencies globally."
echo "Install/test only the repository targeted by the current Codex task."
