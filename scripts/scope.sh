#!/usr/bin/env bash
# scripts/scope.sh — Generic scope lifecycle driver
#
# Single source of truth for all scope actions: up, down, purge.
# Reads scope metadata (compose dirs, data dirs, deps) from scopes/<name>.sh.
# Adding a new scope only requires a new scope file + 3 Makefile lines.
#
# Usage: bash scripts/scope.sh <scope|all> <up|down|purge> [--full]
#   up     — start compose services (with dependency check)
#   down   — stop compose services
#   purge  — stop + remove Docker volumes + wipe data dirs (typed confirmation)
#   all    — operate on all known scopes in correct dependency order
#   --full — (purge only) also delete .env and .htpasswd after purge
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SCOPES_DIR="$ROOT_DIR/scopes"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE="docker compose"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
err()     { echo -e "${RED}  ✗ ERROR:${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

# ── Args ───────────────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <scope|all> <up|down|purge> [--full]" >&2
  exit 1
fi
SCOPE_ARG="$1"
ACTION="$2"
FULL_FLAG="${3:-}"

# Canonical scope order — dependency-safe (network first up, last purged)
ALL_SCOPES_ORDERED=(network identity dev productivity communication observability)

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi
DOMAIN="${DOMAIN:-infra.home}"

# ── load_scope SCOPE — source scope file into current shell ───────────────────
load_scope() {
  local scope="$1"
  local f="$SCOPES_DIR/${scope}.sh"
  if [[ ! -f "$f" ]]; then
    err "Unknown scope: '$scope' (no file at scopes/${scope}.sh)"
    exit 1
  fi
  # Reset all SCOPE_* vars before sourcing to avoid bleed between loads
  SCOPE_NAME="" SCOPE_DESCRIPTION="" SCOPE_COMPOSE_DIRS="" SCOPE_DATA_DIRS=""
  SCOPE_DEPENDS_ON="" SCOPE_SOFT_DEPENDS_ON="" SCOPE_INIT_TASKS=""
  SCOPE_HEALTH_CHECK="" SCOPE_HEALTH_DESC=""
  # shellcheck source=/dev/null
  source "$f"
}

# ── reverse_words "a b c" → "c b a" ──────────────────────────────────────────
reverse_words() {
  local result=()
  [[ -z "${1:-}" ]] && echo "" && return
  for w in $1; do result=("$w" "${result[@]:-}"); done
  echo "${result[*]}"
}

# ══════════════════════════════════════════════════════════════════════════════
# ACTION: up
# ══════════════════════════════════════════════════════════════════════════════
do_up() {
  local scope="$1"
  load_scope "$scope"

  if [[ ! -f "$ENV_FILE" ]]; then
    err ".env not found — run 'make setup' first"
    exit 1
  fi

  # Dependency check (--soft: warns about soft deps, fails on hard deps)
  if [[ -n "${SCOPE_DEPENDS_ON:-}" || -n "${SCOPE_SOFT_DEPENDS_ON:-}" ]]; then
    bash "$SCRIPT_DIR/check-scope-deps.sh" "$scope" --soft || exit 1
  fi

  section "Starting scope: $scope"
  for dir in $SCOPE_COMPOSE_DIRS; do
    info "Up: $dir"
    $COMPOSE -f "$ROOT_DIR/$dir/docker-compose.yml" --env-file "$ENV_FILE" up -d
  done
  success "Scope '$scope' is up"
}

# ══════════════════════════════════════════════════════════════════════════════
# ACTION: down
# ══════════════════════════════════════════════════════════════════════════════
do_down() {
  local scope="$1"
  load_scope "$scope"

  section "Stopping scope: $scope"
  # Stop compose dirs in reverse order
  for dir in $(reverse_words "$SCOPE_COMPOSE_DIRS"); do
    info "Down: $dir"
    $COMPOSE -f "$ROOT_DIR/$dir/docker-compose.yml" down 2>/dev/null || true
  done
  success "Scope '$scope' is down"
}

# ══════════════════════════════════════════════════════════════════════════════
# ACTION: purge — execution kernel (no confirmation; called after confirm)
# ══════════════════════════════════════════════════════════════════════════════
_execute_purge_scope() {
  local scope="$1"
  load_scope "$scope"

  # Stop containers and remove named Docker volumes
  for dir in $(reverse_words "$SCOPE_COMPOSE_DIRS"); do
    info "Down --volumes: $dir"
    $COMPOSE -f "$ROOT_DIR/$dir/docker-compose.yml" down --volumes 2>/dev/null || true
  done

  # Delete bind-mount data directories
  for d in ${SCOPE_DATA_DIRS:-}; do
    if [[ -d "$ROOT_DIR/data/$d" ]]; then
      rm -rf "${ROOT_DIR:?}/data/$d"
      success "Removed data/$d"
    fi
  done

  # Network scope: also remove the shared Docker network
  if [[ "$scope" == "network" ]]; then
    docker network rm infra_net 2>/dev/null \
      && success "Removed Docker network: infra_net" \
      || info "Docker network infra_net not present, skipping"
  fi
}

# ── do_purge SCOPE — single-scope purge with confirmation ─────────────────────
do_purge() {
  local scope="$1"
  load_scope "$scope"

  # Reverse dependency guard: warn if scopes that depend on this one are running
  for s in "${ALL_SCOPES_ORDERED[@]}"; do
    [[ "$s" == "$scope" ]] && continue
    local s_file="$SCOPES_DIR/${s}.sh"
    [[ ! -f "$s_file" ]] && continue
    local s_all_deps
    s_all_deps="$(bash -c "source \"$s_file\"; echo \"\${SCOPE_DEPENDS_ON:-} \${SCOPE_SOFT_DEPENDS_ON:-}\"")"
    if [[ " $s_all_deps " =~ " $scope " ]]; then
      local s_dirs
      s_dirs="$(bash -c "source \"$s_file\"; echo \"\${SCOPE_COMPOSE_DIRS:-}\"")"
      for d in $s_dirs; do
        if [[ -f "$ROOT_DIR/$d/docker-compose.yml" ]] && \
           $COMPOSE -f "$ROOT_DIR/$d/docker-compose.yml" ps --quiet 2>/dev/null | grep -q .; then
          warn "Scope '$s' (depends on '$scope') has running containers — run: make $s-down"
        fi
      done
    fi
  done

  # Confirmation prompt
  echo ""
  echo -e "${RED}${BOLD}  ⚠  PURGE: $scope${RESET}"
  echo "  Will stop containers, remove Docker volumes, and delete:"
  for d in ${SCOPE_DATA_DIRS:-}; do echo "    • data/$d/"; done
  [[ "$FULL_FLAG" == "--full" ]] && echo "    • .env and core/config/traefik/dynamic/.htpasswd (--full)"
  echo ""
  read -rp "  Type 'yes' to confirm: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { info "Aborted."; exit 0; }

  section "Purging scope: $scope"
  _execute_purge_scope "$scope"

  if [[ "$FULL_FLAG" == "--full" ]]; then
    section "Full reset"
    rm -f "$ENV_FILE"       && success "Deleted .env"
    rm -f "$ROOT_DIR/core/config/traefik/dynamic/.htpasswd" && success "Deleted .htpasswd"
  fi

  echo ""
  success "Purge complete: $scope"
  echo "  Restore with: make init && make $scope-up"
}

# ══════════════════════════════════════════════════════════════════════════════
# all-scope variants
# ══════════════════════════════════════════════════════════════════════════════
do_all_up() {
  if [[ ! -f "$ENV_FILE" ]]; then
    err ".env not found — run 'make setup' first"
    exit 1
  fi
  read -ra SCOPES <<< "${ENABLED_SCOPES:-network}"
  for s in "${SCOPES[@]}"; do
    do_up "$s"
  done
}

do_all_down() {
  # Reverse canonical order — gracefully skips scopes that aren't running
  for s in $(reverse_words "${ALL_SCOPES_ORDERED[*]}"); do
    [[ ! -f "$SCOPES_DIR/${s}.sh" ]] && continue
    do_down "$s"
  done
}

do_all_purge() {
  echo ""
  echo -e "${RED}${BOLD}  ⚠  PURGE ALL SCOPES${RESET}"
  echo "  Stops ALL containers, removes ALL Docker volumes, deletes ALL data:"
  for s in "${ALL_SCOPES_ORDERED[@]}"; do
    [[ ! -f "$SCOPES_DIR/${s}.sh" ]] && continue
    bash -c "source \"$SCOPES_DIR/${s}.sh\"; for d in \${SCOPE_DATA_DIRS:-}; do echo \"    • data/\$d/\"; done"
  done
  [[ "$FULL_FLAG" == "--full" ]] && echo "  --full: also deletes .env and .htpasswd"
  echo ""
  read -rp "  Type 'yes' to confirm: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { info "Aborted."; exit 0; }

  # Purge in reverse dependency order (leaves network last)
  for s in $(reverse_words "${ALL_SCOPES_ORDERED[*]}"); do
    [[ ! -f "$SCOPES_DIR/${s}.sh" ]] && continue
    section "Purging: $s"
    _execute_purge_scope "$s"
  done

  if [[ "$FULL_FLAG" == "--full" ]]; then
    section "Full reset"
    rm -f "$ENV_FILE"       && success "Deleted .env"
    rm -f "$ROOT_DIR/core/config/traefik/dynamic/.htpasswd" && success "Deleted .htpasswd"
  fi

  echo ""
  success "All scopes purged."
  echo "  Start fresh with: make setup"
}

# ══════════════════════════════════════════════════════════════════════════════
# Dispatch
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$SCOPE_ARG" == "all" ]]; then
  case "$ACTION" in
    up)    do_all_up ;;
    down)  do_all_down ;;
    purge) do_all_purge ;;
    *) err "Unknown action: '$ACTION'. Valid: up | down | purge"; exit 1 ;;
  esac
else
  case "$ACTION" in
    up)    do_up    "$SCOPE_ARG" ;;
    down)  do_down  "$SCOPE_ARG" ;;
    purge) do_purge "$SCOPE_ARG" ;;
    *) err "Unknown action: '$ACTION'. Valid: up | down | purge"; exit 1 ;;
  esac
fi
