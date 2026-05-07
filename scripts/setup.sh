#!/usr/bin/env bash
# scripts/setup.sh — Interactive setup wizard (scope-aware)
# Prompts for scope selection + required values, auto-generates secrets,
# writes .env, then hands off to scripts/init.sh for bootstrap.
#
# Usage: bash scripts/setup.sh
#        make setup
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

# ── Colour helpers ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
err()     { echo -e "${RED}  ✗ ERROR:${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

# ── Prerequisite check ─────────────────────────────────────────────────────────
section "Checking prerequisites"

MISSING=()
for cmd in docker openssl; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  err "Required commands not found: ${MISSING[*]}"
  exit 1
fi
success "docker and openssl found"

# Check for bcrypt capability (htpasswd or python3)
BCRYPT_METHOD=""
if command -v htpasswd &>/dev/null; then
  BCRYPT_METHOD="htpasswd"
elif python3 -c "import bcrypt" 2>/dev/null; then
  BCRYPT_METHOD="python"
else
  warn "Neither 'htpasswd' (apache2-utils) nor python3-bcrypt found."
  warn "WireGuard password hash will be skipped — set WG_PASSWORD_HASH manually."
fi

# ── Resume detection ───────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  echo ""
  warn ".env already exists at $ENV_FILE"
  echo -e "  ${BOLD}[r]${RESET} Re-run setup and overwrite .env"
  echo -e "  ${BOLD}[i]${RESET} Skip to init.sh (keep existing .env)"
  echo -e "  ${BOLD}[q]${RESET} Quit"
  read -rp "  Choice [r/i/q]: " RESUME_CHOICE
  case "${RESUME_CHOICE,,}" in
    i) info "Skipping setup, running init.sh with existing .env..."
       exec bash "$SCRIPT_DIR/init.sh" ;;
    q) info "Aborted."; exit 0 ;;
    r) info "Re-running setup — .env will be overwritten." ;;
    *) err "Invalid choice."; exit 1 ;;
  esac
fi

# ── Helpers ────────────────────────────────────────────────────────────────────

# prompt_value VAR_NAME "Description" "default_value"
prompt_value() {
  local var="$1" desc="$2" default="$3"
  local prompt_str
  if [[ -n "$default" ]]; then
    prompt_str="  ${desc} [${default}]: "
  else
    prompt_str="  ${desc}: "
  fi
  read -rp "$prompt_str" INPUT
  if [[ -z "$INPUT" && -n "$default" ]]; then
    INPUT="$default"
  fi
  printf -v "$var" '%s' "$INPUT"
}

# prompt_password VAR_NAME "Description"
prompt_password() {
  local var="$1" desc="$2"
  local p1 p2
  while true; do
    read -rsp "  ${desc}: " p1; echo
    if [[ ${#p1} -lt 12 ]]; then
      warn "Password must be at least 12 characters. Try again."
      continue
    fi
    read -rsp "  Confirm ${desc}: " p2; echo
    if [[ "$p1" != "$p2" ]]; then
      warn "Passwords do not match. Try again."
      continue
    fi
    break
  done
  printf -v "$var" '%s' "$p1"
}

# bcrypt_hash plaintext  →  stdout
bcrypt_hash() {
  local plain="$1"
  if [[ "$BCRYPT_METHOD" == "htpasswd" ]]; then
    htpasswd -bnBC 10 "" "$plain" | tr -d ':' | tr -d '\n'
  elif [[ "$BCRYPT_METHOD" == "python" ]]; then
    python3 -c "import bcrypt, sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode())" "$plain"
  else
    echo ""
  fi
}

# detect_host_ip  →  stdout
detect_host_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1
}

# scope_enabled SCOPE_NAME → returns 0 (true) if in ENABLED_SCOPES
scope_enabled() { [[ " ${ENABLED_SCOPES} " =~ " $1 " ]]; }

# ── Section 0 — Scope selection ───────────────────────────────────────────────
section "0 / 3  Deployment scopes"
echo "  Select which service groups to deploy."
echo "  Each scope can be enabled or disabled independently."
echo "  'network' (VPN, DNS, CA, Traefik) is always required."
echo ""

# Helper: prompt y/n for a scope and print "true" or "false"
prompt_scope() {
  local name="$1" desc="$2" notes="$3" default="$4"
  local yn ynhint
  [[ "$default" == "y" ]] && ynhint="Y/n" || ynhint="y/N"
  # All display output goes to stderr so it isn't captured by $()
  echo -e "  ${GREEN}●${RESET} ${BOLD}${name}${RESET}: ${desc}" >&2
  [[ -n "$notes" ]] && echo -e "    ${YELLOW}Note:${RESET} ${notes}" >&2
  read -rp "    Enable? [${ynhint}]: " yn
  [[ -z "$yn" ]] && yn="$default"
  case "${yn,,}" in y|yes) echo "true" ;; *) echo "false" ;; esac
}

echo -e "  ${GREEN}●${RESET} ${BOLD}network${RESET} (always on): VPN (WireGuard), DNS (Technitium), CA (Step CA), Traefik"
echo "    (always enabled — required by all other scopes)"
echo ""

SCOPE_IDENTITY="$(    prompt_scope "identity"      "SSO / OIDC provider (Authentik)" \
                        "required by calendar; enables OIDC login for all other scopes" "y")"
echo ""

SCOPE_DEV="$(         prompt_scope "dev"           "Git hosting + CI/CD (Forgejo + Woodpecker)" \
                        "OIDC login available if identity is also enabled" "y")"
echo ""

SCOPE_PRODUCTIVITY="$(prompt_scope "productivity"  "File sharing, mail, calendar (SFTPGo, Stalwart, Radicale)" \
                        "Radicale (calendar) requires identity — will be auto-enabled if needed" "y")"
echo ""

SCOPE_COMMUNICATION="$(prompt_scope "communication" "Matrix chat server + Element Web (Dendrite)" \
                        "OIDC optional if identity is also enabled" "y")"
echo ""

SCOPE_OBSERVABILITY="$(prompt_scope "observability" "Metrics, logs, dashboards (Prometheus, Loki, Grafana)" \
                        "Grafana OIDC available if identity is also enabled" "y")"
echo ""

# ── Hard dependency enforcement ────────────────────────────────────────────────
# Radicale uses Authentik forward-auth — identity is mandatory with productivity
if [[ "$SCOPE_PRODUCTIVITY" == "true" && "$SCOPE_IDENTITY" == "false" ]]; then
  warn "Radicale (calendar) uses Authentik forward-auth middleware."
  warn "The 'productivity' scope requires 'identity' — automatically enabling it."
  SCOPE_IDENTITY="true"
fi

# ── Build ENABLED_SCOPES (space-separated, network always first) ───────────────
ENABLED_SCOPES="network"
[[ "$SCOPE_IDENTITY"      == "true" ]] && ENABLED_SCOPES="$ENABLED_SCOPES identity"
[[ "$SCOPE_DEV"           == "true" ]] && ENABLED_SCOPES="$ENABLED_SCOPES dev"
[[ "$SCOPE_PRODUCTIVITY"  == "true" ]] && ENABLED_SCOPES="$ENABLED_SCOPES productivity"
[[ "$SCOPE_COMMUNICATION" == "true" ]] && ENABLED_SCOPES="$ENABLED_SCOPES communication"
[[ "$SCOPE_OBSERVABILITY" == "true" ]] && ENABLED_SCOPES="$ENABLED_SCOPES observability"

echo ""
info "Enabled scopes: ${BOLD}${ENABLED_SCOPES}${RESET}"

# ── Declare all variables (empty defaults prevent unbound errors with set -u) ──
DOMAIN="" HOST_IP="" MATRIX_SERVER_NAME="" WOODPECKER_ADMIN=""
TRAEFIK_DASHBOARD_PASSWORD="" TECHNITIUM_ADMIN_PASSWORD=""
WG_PASSWORD="" WG_PASSWORD_HASH=""
AUTHENTIK_POSTGRES_PASSWORD="" AUTHENTIK_SECRET_KEY=""
FORGEJO_POSTGRES_PASSWORD="" WOODPECKER_AGENT_SECRET=""
SFTPGO_ADMIN_PASSWORD="" STALWART_ADMIN_PASSWORD=""
DENDRITE_POSTGRES_PASSWORD="" GRAFANA_ADMIN_PASSWORD=""

# ── Section 1 — Infrastructure configuration ──────────────────────────────────
section "1 / 3  Infrastructure configuration"

prompt_value DOMAIN "Internal domain (used for all service URLs)" "infra.home"
[[ -z "$DOMAIN" ]] && { err "DOMAIN cannot be empty."; exit 1; }

DETECTED_IP="$(detect_host_ip)"
prompt_value HOST_IP "Server LAN IP (VPN clients connect here)" "${DETECTED_IP:-192.168.1.10}"
[[ -z "$HOST_IP" ]] && { err "HOST_IP cannot be empty."; exit 1; }

if scope_enabled "communication"; then
  prompt_value MATRIX_SERVER_NAME "Matrix server name (for Dendrite/Element)" "$DOMAIN"
fi

if scope_enabled "dev"; then
  prompt_value WOODPECKER_ADMIN "Woodpecker CI admin username" "admin"
fi

# ── Section 2 — Passwords ──────────────────────────────────────────────────────
section "2 / 3  Passwords"
echo "  Passwords must be at least 12 characters and confirmed twice."
echo "  Only passwords relevant to your selected scopes are prompted."
echo ""

# network — always required
prompt_password TRAEFIK_DASHBOARD_PASSWORD "Traefik dashboard password (user: admin)"
prompt_password TECHNITIUM_ADMIN_PASSWORD  "Technitium DNS admin password"
prompt_password WG_PASSWORD                "WireGuard VPN web UI password"

if scope_enabled "identity"; then
  prompt_password AUTHENTIK_POSTGRES_PASSWORD "Authentik database password"
fi
if scope_enabled "dev"; then
  prompt_password FORGEJO_POSTGRES_PASSWORD "Forgejo database password"
fi
if scope_enabled "productivity"; then
  prompt_password SFTPGO_ADMIN_PASSWORD   "SFTPGo admin password"
  prompt_password STALWART_ADMIN_PASSWORD "Stalwart Mail admin password"
fi
if scope_enabled "communication"; then
  prompt_password DENDRITE_POSTGRES_PASSWORD "Dendrite (Matrix) database password"
fi
if scope_enabled "observability"; then
  prompt_password GRAFANA_ADMIN_PASSWORD "Grafana admin password"
fi

# ── Section 3 — Auto-generate secrets ─────────────────────────────────────────
section "3 / 3  Generating secrets"

if scope_enabled "identity"; then
  info "Generating AUTHENTIK_SECRET_KEY (base64-60)..."
  AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')"
  success "AUTHENTIK_SECRET_KEY generated"
fi

if scope_enabled "dev"; then
  info "Generating WOODPECKER_AGENT_SECRET (hex-32)..."
  WOODPECKER_AGENT_SECRET="$(openssl rand -hex 32)"
  success "WOODPECKER_AGENT_SECRET generated"
fi

if [[ -n "$BCRYPT_METHOD" ]]; then
  info "Hashing WireGuard password (bcrypt, cost 10)..."
  WG_PASSWORD_HASH="$(bcrypt_hash "$WG_PASSWORD")"
  success "WG_PASSWORD_HASH generated"
else
  warn "Skipping WG_PASSWORD_HASH — set it manually in .env after install."
fi

info "Generating Traefik dashboard htpasswd entry..."
TRAEFIK_HTPASSWD=""
if [[ "$BCRYPT_METHOD" == "htpasswd" ]]; then
  TRAEFIK_HTPASSWD="$(htpasswd -bnBC 10 "admin" "$TRAEFIK_DASHBOARD_PASSWORD" | sed 's/\$/\$\$/g' | tr -d '\n')"
  success "Traefik htpasswd entry generated"
elif [[ "$BCRYPT_METHOD" == "python" ]]; then
  _HASH="$(python3 -c "import bcrypt, sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode())" "$TRAEFIK_DASHBOARD_PASSWORD")"
  _ESCAPED="${_HASH//\$/\$\$}"
  TRAEFIK_HTPASSWD="admin:${_ESCAPED}"
  success "Traefik htpasswd entry generated"
else
  warn "Skipping Traefik htpasswd — update core/config/traefik/dynamic/.htpasswd manually."
fi

# ── Write .htpasswd ────────────────────────────────────────────────────────────
if [[ -n "${TRAEFIK_HTPASSWD:-}" ]]; then
  mkdir -p "$ROOT_DIR/core/config/traefik/dynamic"
  echo "$TRAEFIK_HTPASSWD" > "$ROOT_DIR/core/config/traefik/dynamic/.htpasswd"
  success "Wrote core/config/traefik/dynamic/.htpasswd"
fi

# ── Write .env ─────────────────────────────────────────────────────────────────
info "Writing $ENV_FILE ..."

{
  echo "# Generated by scripts/setup.sh on $(date -u +\"%Y-%m-%d %H:%M UTC\")"
  echo "# DO NOT commit this file to version control."
  echo ""
  echo "# -- Deployment scopes -------------------------------------------------------"
  echo "# Space-separated list. Controls which compose stacks init.sh will start."
  echo "ENABLED_SCOPES='${ENABLED_SCOPES}'"
  echo ""
  echo "# -- Infrastructure ----------------------------------------------------------"
  echo "DOMAIN='${DOMAIN}'"
  echo "HOST_IP='${HOST_IP}'"
  echo ""
  echo "# -- Step CA (auto-populated by init.sh after first-run) ---------------------"
  echo "STEP_CA_FINGERPRINT="
  echo ""
  echo "# -- Traefik / network -------------------------------------------------------"
  echo "TECHNITIUM_ADMIN_PASSWORD='${TECHNITIUM_ADMIN_PASSWORD}'"
  echo ""
  echo "# -- WireGuard ---------------------------------------------------------------"
  echo "WG_DEFAULT_ADDRESS=10.8.0.x"
  echo "WG_DEFAULT_DNS='${HOST_IP}'"
  echo "WG_PASSWORD_HASH='${WG_PASSWORD_HASH}'"
  echo ""

  if scope_enabled "identity"; then
    echo "# -- Authentik ---------------------------------------------------------------"
    echo "AUTHENTIK_SECRET_KEY='${AUTHENTIK_SECRET_KEY}'"
    echo "AUTHENTIK_POSTGRES_PASSWORD='${AUTHENTIK_POSTGRES_PASSWORD}'"
    echo "# FILL AFTER UI: Authentik -> Outposts -> create/view token  (run 'make configure-oidc')"
    echo "AUTHENTIK_OUTPOST_TOKEN="
    echo ""
  fi

  if scope_enabled "dev"; then
    echo "# -- Forgejo + Woodpecker ---------------------------------------------------"
    echo "FORGEJO_POSTGRES_PASSWORD='${FORGEJO_POSTGRES_PASSWORD}'"
    echo "# AUTO-POPULATED by configure-oidc.sh after Forgejo first boot"
    echo "FORGEJO_ADMIN_TOKEN="
    echo "WOODPECKER_ADMIN='${WOODPECKER_ADMIN}'"
    echo "WOODPECKER_AGENT_SECRET='${WOODPECKER_AGENT_SECRET}'"
    echo "# FILL AFTER UI: Forgejo -> Settings -> Applications -> OAuth app  (run 'make configure-oidc')"
    echo "WOODPECKER_FORGEJO_CLIENT="
    echo "WOODPECKER_FORGEJO_SECRET="
    echo ""
  fi

  if scope_enabled "productivity"; then
    echo "# -- SFTPGo -----------------------------------------------------------------"
    echo "SFTPGO_ADMIN_PASSWORD='${SFTPGO_ADMIN_PASSWORD}'"
    echo "# FILL AFTER UI: Authentik -> Applications -> create OIDC app  (run 'make configure-oidc')"
    echo "SFTPGO_OIDC_CLIENT_ID="
    echo "SFTPGO_OIDC_CLIENT_SECRET="
    echo ""
    echo "# -- Stalwart Mail ----------------------------------------------------------"
    echo "STALWART_ADMIN_PASSWORD='${STALWART_ADMIN_PASSWORD}'"
    echo ""
    echo "# -- Radicale ---------------------------------------------------------------"
    echo "# Auto-populated by init.sh"
    echo "RADICALE_USERS="
    echo ""
  fi

  if scope_enabled "communication"; then
    echo "# -- Dendrite (Matrix) ------------------------------------------------------"
    echo "DENDRITE_POSTGRES_PASSWORD='${DENDRITE_POSTGRES_PASSWORD}'"
    echo "MATRIX_SERVER_NAME='${MATRIX_SERVER_NAME}'"
    echo ""
  fi

  if scope_enabled "observability"; then
    echo "# -- Grafana ----------------------------------------------------------------"
    echo "GRAFANA_ADMIN_PASSWORD='${GRAFANA_ADMIN_PASSWORD}'"
    echo "# FILL AFTER UI: Authentik -> Applications -> create OIDC app  (run 'make configure-oidc')"
    echo "GRAFANA_OIDC_CLIENT_ID="
    echo "GRAFANA_OIDC_CLIENT_SECRET="
    echo ""
  fi
} > "$ENV_FILE"

success ".env written"

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
info "Setup complete."
echo ""
echo -e "  Enabled scopes: ${BOLD}${ENABLED_SCOPES}${RESET}"
echo ""
if scope_enabled "identity" || scope_enabled "dev" || scope_enabled "productivity" || scope_enabled "observability"; then
  echo -e "  ${YELLOW}Post-UI step required:${RESET} After services are running, run:"
  echo -e "    ${BOLD}make configure-oidc${RESET}"
  echo ""
fi
info "Starting infrastructure bootstrap..."
echo ""
exec bash "$SCRIPT_DIR/init.sh"
