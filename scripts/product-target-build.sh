#!/usr/bin/env bash
# Fixed Luckfox RK3506 target entrypoint; this repository has no target selector.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${GAR_TARGET:-}" && "$GAR_TARGET" != luckfox-rk3506 ]]; then
  echo "GarStreamRx has fixed target luckfox-rk3506, not $GAR_TARGET" >&2
  exit 2
fi
export GAR_TARGET=luckfox-rk3506
export GAR_TARGET_ARTIFACT_MANIFEST="${repo_root}/config/artifact.json"
exec "${repo_root}/scripts/target/package.sh" "$@"
