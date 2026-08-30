#!/usr/bin/env bash
# Compatibility wrapper; implementation lives in the Target Capsule.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${repo_root}/scripts/target/configure-target" "$@"
