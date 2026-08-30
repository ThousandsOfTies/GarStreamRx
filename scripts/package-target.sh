#!/usr/bin/env bash
# Stable Product target-build entrypoint. The selected Deployment Profile owns
# composition; its Target Capsule owns implementation.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
requested_deployment="${GAR_DEPLOYMENT:-}"
if [[ -f "${repo_root}/config/product.env" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/config/product.env"
fi
if [[ -n "$requested_deployment" ]]; then
  export GAR_DEPLOYMENT="$requested_deployment"
fi
unset requested_deployment
exec python3 "${repo_root}/scripts/package_target.py" "$@"
