#!/bin/sh
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

grep -Fq 'runs-on: ubuntu-latest' .github/workflows/ci.yml
grep -Fq 'node Scripts/test-web-demo.mjs' .github/workflows/ci.yml
grep -Fq 'python Scripts/test-web-demo-e2e.py' .github/workflows/ci.yml
grep -Fq 'exec ./Scripts/preflight.sh' Scripts/pre-push.sh

echo "Preflight parity: OK"
