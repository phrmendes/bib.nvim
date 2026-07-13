#!/usr/bin/env bash
set -euo pipefail

echo "==> stylua"
stylua --check lua/ tests/

echo ""
echo "All checks passed."
