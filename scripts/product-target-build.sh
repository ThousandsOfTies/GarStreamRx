#!/usr/bin/env bash
# Compatibility entrypoint for GaplessAgentRuntime.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${repo_root}/scripts/package-target.sh" "$@"
