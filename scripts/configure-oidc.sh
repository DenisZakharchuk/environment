#!/usr/bin/env bash
# scripts/configure-oidc.sh — Phase-2 interactive helper for post-UI tokens
# Driven by SCOPE_VARS_POST_UI from each enabled scope file.
# Run after services are up and OIDC apps have been created.
#
# Usage: bash scripts/configure-oidc.sh
#        make configure-oidc
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
SCOPES_DIR="$ROOT_DIR/scopes"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
section() { echo -e "\n${BOLD}--- $1 / $2  $3 ---${RESET}"; }

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found. Run 'make setup' first." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"
DOMAIN="${DOMAIN:-infra.local}"

# Read ENABLED_SCOPES — default to all scopes for backwards compatibility
read -ra ENABLED_SCOPES_ARR <<< "${ENABLED_SCOPES:-network identity dev productivity communication observability}"

# ── Helper: prompt for a single env var, write to .env ────────────────────────
# set_env_var KEY "Description" "Where to find the value"
set_env_var() {
  local key="$1" desc="$2" hint="$3"
  local current
  current="$(grep "^${key}=" "$ENV_FILE" | cut -d= -f2- || true)"

  echo ""
  echo -e "  ${BOLD}${desc}${RESET}"
  [[ -n "$hint" ]] && echo -e "  ${CYAN}Where:${RESET} ${hint}"
  if [[ -n "$current" ]]; then
    echo -e "  ${YELLOW}Current value:${RESET} ${current}"
    read -rp "  New value (Enter to keep current): " INPUT
    [[ -z "$INPUT" ]] && return
  else
    read -rp "  Value: " INPUT
    [[ -z "$INPUT" ]] && { warn "Skipped (empty)."; return; }
  fi

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${INPUT}|" "$ENV_FILE"
  else
    echo "${key}=${INPUT}" >> "$ENV_FILE"
  fi
  success "${key} saved"
}

# ── Per-scope configuration handlers ──────────────────────────────────────────
# Each function receives: N TOTAL
# and must handle all vars listed in that scope's SCOPE_VARS_POST_UI.

configure_scope_identity() {
  local n="$1" total="$2"
  section "$n" "$total" "Authentik Outpost Token  [identity]"
  echo "  The proxy outpost token allows Traefik forward-auth to communicate"
  echo "  with Authentik. Create (or view) the outpost in the Authentik UI."
  echo ""
  echo "  Steps:"
  echo "    1. Open https://auth.${DOMAIN}"
  echo "    2. Admin -> Outposts -> Create (or select existing Proxy outpost)"
  echo "    3. Copy the outpost token from the outpost detail page"
  set_env_var "AUTHENTIK_OUTPOST_TOKEN" \
    "Authentik proxy outpost token" \
    "https://auth.${DOMAIN} -> Admin -> Outposts -> [outpost] -> Token"
}

configure_scope_dev() {
  local n="$1" total="$2"
  section "$n" "$total" "Woodpecker CI + Forgejo OAuth  [dev]"

  echo "  Part A — Woodpecker Forgejo OAuth application"
  echo ""
  echo "  Steps:"
  echo "    1. Open https://git.${DOMAIN}"
  echo "    2. Profile icon -> Settings -> Applications -> OAuth2 Applications"
  echo "    3. Create application named 'Woodpecker CI'"
  echo "       - Redirect URI: https://ci.${DOMAIN}/authorize"
  echo "    4. Copy Client ID and Client Secret"
  set_env_var "WOODPECKER_FORGEJO_CLIENT" \
    "Woodpecker Forgejo OAuth Client ID" \
    "https://git.${DOMAIN} -> Settings -> Applications -> OAuth2"
  set_env_var "WOODPECKER_FORGEJO_SECRET" \
    "Woodpecker Forgejo OAuth Client Secret" \
    "https://git.${DOMAIN} -> Settings -> Applications -> OAuth2"

  echo ""
  echo "  Part B — Forgejo admin access token (optional, for CI scripting)"
  echo ""
  echo "  Steps:"
  echo "    1. Open https://git.${DOMAIN}"
  echo "    2. Profile icon -> Settings -> Applications -> Access Tokens"
  echo "    3. Generate token with desired permissions"
  set_env_var "FORGEJO_ADMIN_TOKEN" \
    "Forgejo personal access token (optional)" \
    "https://git.${DOMAIN} -> Settings -> Applications -> Access Tokens"
}

configure_scope_productivity() {
  local n="$1" total="$2"
  section "$n" "$total" "SFTPGo OIDC Application  [productivity]"
  echo "  Steps:"
  echo "    1. Open https://auth.${DOMAIN}"
  echo "    2. Admin -> Providers -> Create -> OAuth2/OpenID Connect Provider"
  echo "       - Name: SFTPGo"
  echo "       - Redirect URI: https://files.${DOMAIN}/web/oidc/redirect"
  echo "    3. Admin -> Applications -> Create, link to the SFTPGo provider"
  echo "    4. Copy Client ID and Client Secret from the provider detail page"
  set_env_var "SFTPGO_OIDC_CLIENT_ID" \
    "SFTPGo OIDC Client ID" \
    "https://auth.${DOMAIN} -> Admin -> Providers -> SFTPGo"
  set_env_var "SFTPGO_OIDC_CLIENT_SECRET" \
    "SFTPGo OIDC Client Secret" \
    "https://auth.${DOMAIN} -> Admin -> Providers -> SFTPGo"
}

configure_scope_observability() {
  local n="$1" total="$2"
  section "$n" "$total" "Grafana OIDC Application  [observability]"
  echo "  Steps:"
  echo "    1. Open https://auth.${DOMAIN}"
  echo "    2. Admin -> Providers -> Create -> OAuth2/OpenID Connect Provider"
  echo "       - Name: Grafana"
  echo "       - Redirect URI: https://grafana.${DOMAIN}/login/generic_oauth"
  echo "    3. Admin -> Applications -> Create, link to the Grafana provider"
  echo "    4. Copy Client ID and Client Secret from the provider detail page"
  set_env_var "GRAFANA_OIDC_CLIENT_ID" \
    "Grafana OIDC Client ID" \
    "https://auth.${DOMAIN} -> Admin -> Providers -> Grafana"
  set_env_var "GRAFANA_OIDC_CLIENT_SECRET" \
    "Grafana OIDC Client Secret" \
    "https://auth.${DOMAIN} -> Admin -> Providers -> Grafana"
}

# ── Build ordered list of scopes that have post-UI vars ───────────────────────
SCOPES_WITH_POST_UI=()
for scope in "${ENABLED_SCOPES_ARR[@]}"; do
  scope_file="$SCOPES_DIR/${scope}.sh"
  [[ ! -f "$scope_file" ]] && continue
  # Read SCOPE_VARS_POST_UI from the scope file without polluting env
  post_ui="$(bash -c "source \"$scope_file\"; echo \"\${SCOPE_VARS_POST_UI:-}\"")"
  [[ -z "$post_ui" ]] && continue
  # Only include if a handler function exists for this scope
  if declare -f "configure_scope_${scope}" > /dev/null 2>&1; then
    SCOPES_WITH_POST_UI+=("$scope")
  fi
done

TOTAL="${#SCOPES_WITH_POST_UI[@]}"

# ── Entry ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Post-UI OIDC / Token Configuration${RESET}"
echo "  Fills in tokens that can only be obtained after services are running."
echo "  Skip any step by pressing Enter — re-run this script at any time."
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
  warn "No post-UI tokens needed for your enabled scopes (${ENABLED_SCOPES:-none})."
  exit 0
fi

info "Enabled scopes with post-UI tokens: ${SCOPES_WITH_POST_UI[*]}"

# ── Run each handler ───────────────────────────────────────────────────────────
N=0
RESTARTED_SCOPES=()
for scope in "${SCOPES_WITH_POST_UI[@]}"; do
  N=$((N + 1))
  "configure_scope_${scope}" "$N" "$TOTAL"
  RESTARTED_SCOPES+=("$scope")
done

# ── Restart reminder ───────────────────────────────────────────────────────────
echo ""
success "configure-oidc complete."
echo ""
echo "  Restart affected scopes to pick up the new values:"
for scope in "${RESTARTED_SCOPES[@]}"; do
  echo "    make scope-${scope}"
done
echo ""
echo "  Or restart all enabled scopes:"
echo "    make scope-all"
