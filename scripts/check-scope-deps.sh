#!/usr/bin/env bash
# scripts/check-scope-deps.sh — Verify a scope's dependencies are healthy
# Used by init.sh and scope Makefile targets before starting services.
#
# Usage: bash scripts/check-scope-deps.sh <scope_name> [--soft]
#   --soft  Also check SCOPE_SOFT_DEPENDS_ON (warn only, do not abort)
#
# Exit codes:
#   0  All hard dependencies healthy
#   1  One or more hard dependencies unreachable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SCOPES_DIR="$ROOT_DIR/scopes"
ENV_FILE="$ROOT_DIR/.env"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
err()     { echo -e "${RED}  ✗${RESET} $*" >&2; }

# ── Args ───────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <scope_name> [--soft]" >&2
  exit 1
fi
TARGET_SCOPE="$1"
CHECK_SOFT="${2:-}"

# ── Load .env for variable substitution in health checks ──────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi
DOMAIN="${DOMAIN:-infra.home}"
HOST_IP="${HOST_IP:-}"

# ── Load target scope to find its dependencies ────────────────────────────────
SCOPE_FILE="$SCOPES_DIR/${TARGET_SCOPE}.sh"
if [[ ! -f "$SCOPE_FILE" ]]; then
  err "Unknown scope: '${TARGET_SCOPE}' (no file at scopes/${TARGET_SCOPE}.sh)"
  exit 1
fi
# shellcheck source=/dev/null
source "$SCOPE_FILE"

HARD_DEPS="${SCOPE_DEPENDS_ON:-}"
SOFT_DEPS="${SCOPE_SOFT_DEPENDS_ON:-}"

[[ -z "$HARD_DEPS" && -z "$SOFT_DEPS" ]] && exit 0

# ── Check function ─────────────────────────────────────────────────────────────
# check_scope DEP_SCOPE_NAME IS_HARD
# Returns 0 if healthy, 1 if not
check_scope() {
  local dep_name="$1" is_hard="$2"
  local dep_file="$SCOPES_DIR/${dep_name}.sh"

  if [[ ! -f "$dep_file" ]]; then
    err "Dependency scope '${dep_name}' has no scope file — cannot check"
    [[ "$is_hard" == "hard" ]] && return 1 || return 0
  fi

  # Load dep scope in a subshell to avoid variable pollution
  local dep_health dep_desc
  dep_health="$(bash -c "source \"$dep_file\"; echo \"\${SCOPE_HEALTH_CHECK:-}\"")"
  dep_desc="$(bash -c "source \"$dep_file\"; echo \"\${SCOPE_HEALTH_DESC:-scope ${dep_name}}\"")"

  if [[ -z "$dep_health" ]]; then
    warn "Scope '${dep_name}' has no SCOPE_HEALTH_CHECK defined — assuming healthy"
    return 0
  fi

  # Substitute $DOMAIN and $HOST_IP
  local check_cmd
  check_cmd="$(eval echo "$dep_health")"

  info "Checking dependency '${dep_name}': ${dep_desc}"

  if eval "$check_cmd" 2>/dev/null; then
    success "Scope '${dep_name}' is healthy"
    return 0
  else
    if [[ "$is_hard" == "hard" ]]; then
      err "Scope '${dep_name}' is NOT reachable (hard dependency of '${TARGET_SCOPE}')"
      err "Start it first: make ${dep_name}-up"
      return 1
    else
      warn "Scope '${dep_name}' is NOT reachable (soft dependency — services may have reduced functionality)"
      return 0
    fi
  fi
}

# ── Run checks ─────────────────────────────────────────────────────────────────
FAILED=0

for dep in $HARD_DEPS; do
  check_scope "$dep" "hard" || FAILED=1
done

if [[ "$CHECK_SOFT" == "--soft" ]]; then
  for dep in $SOFT_DEPS; do
    check_scope "$dep" "soft" || true
  done
fi

exit $FAILED
