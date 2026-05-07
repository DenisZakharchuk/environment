#!/usr/bin/env bash
# scripts/init.sh — Non-interactive infrastructure bootstrap (scope-driven)
# Requires a fully populated .env (run 'make setup' first).
# Safe to re-run — every step is idempotent.
#
# Usage: bash scripts/init.sh
#        make init
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}==>${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  !${RESET} $*"; }
err()     { echo -e "${RED}  ✗ ERROR:${RESET} $*" >&2; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

# ── Load .env ──────────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  err ".env not found. Run 'make setup' first to generate it interactively."
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

[[ -z "${DOMAIN:-}" ]] && { err "DOMAIN is not set in .env"; exit 1; }

# ── Parse enabled scopes ───────────────────────────────────────────────────────
# ENABLED_SCOPES is a space-separated string written by setup.sh.
# Default to "network" if not present (legacy .env support).
read -ra SCOPES <<< "${ENABLED_SCOPES:-network}"

scope_enabled() { local s; for s in "${SCOPES[@]}"; do [[ "$s" == "$1" ]] && return 0; done; return 1; }

info "Enabled scopes: ${BOLD}${SCOPES[*]}${RESET}"

# ── Docker network ─────────────────────────────────────────────────────────────
section "Docker network"
info "Creating shared Docker network: infra_net"
docker network create infra_net 2>/dev/null && success "infra_net created" \
  || success "infra_net already exists"

# ── Data directories — per scope ───────────────────────────────────────────────
section "Data directories"
info "Creating data directories for enabled scopes..."

declare -A SCOPE_DIRS
SCOPE_DIRS["network"]="step-ca traefik technitium wireguard"
SCOPE_DIRS["identity"]="authentik-postgres authentik-media authentik-certs authentik-redis"
SCOPE_DIRS["dev"]="forgejo forgejo-postgres woodpecker"
SCOPE_DIRS["productivity"]="sftpgo stalwart radicale"
SCOPE_DIRS["communication"]="dendrite-postgres dendrite-media dendrite-keys"
SCOPE_DIRS["observability"]="prometheus grafana loki"

for scope in "${SCOPES[@]}"; do
  if [[ -n "${SCOPE_DIRS[$scope]:-}" ]]; then
    for d in ${SCOPE_DIRS[$scope]}; do
      mkdir -p "$ROOT_DIR/data/$d"
    done
    success "  ${scope}: data dirs ready"
  fi
done

# ── Step CA init (network scope) ───────────────────────────────────────────────
section "Step CA"
if scope_enabled "network"; then
  info "Checking Step CA"
  if [[ -f "$ROOT_DIR/data/step-ca/config/ca.json" ]]; then
    success "Step CA already initialized, skipping"
  else
    info "Initializing Step CA (pulling smallstep/step-ca if needed)..."
    docker run --rm \
      -v "$ROOT_DIR/data/step-ca:/home/step" \
      -e DOCKER_STEPCA_INIT_NAME="Infra Local CA" \
      -e DOCKER_STEPCA_INIT_DNS_NAMES="ca.${DOMAIN},step-ca,localhost" \
      -e DOCKER_STEPCA_INIT_PROVISIONER_NAME="admin" \
      -e DOCKER_STEPCA_INIT_ADDRESS=":9000" \
      -e DOCKER_STEPCA_INIT_ACME="true" \
      smallstep/step-ca:latest step ca init --acme --non-interactive
    success "Step CA initialized"
  fi

  info "Reading Step CA root certificate fingerprint"
  FINGERPRINT="$(docker run --rm \
    -v "$ROOT_DIR/data/step-ca:/home/step" \
    smallstep/step-ca:latest \
    step certificate fingerprint /home/step/certs/root_ca.crt 2>/dev/null || true)"

  if [[ -n "$FINGERPRINT" ]]; then
    sed -i "s|^STEP_CA_FINGERPRINT=.*|STEP_CA_FINGERPRINT=${FINGERPRINT}|" "$ENV_FILE"
    success "STEP_CA_FINGERPRINT updated in .env: ${FINGERPRINT}"
  else
    warn "Could not read fingerprint — check Step CA data directory"
  fi
else
  warn "network scope not enabled — skipping Step CA init"
fi

# ── Dendrite Matrix signing key (communication scope) ─────────────────────────
section "Dendrite signing key"
if scope_enabled "communication"; then
  DENDRITE_KEY="$ROOT_DIR/data/dendrite-keys/matrix_key.pem"
  if [[ -f "$DENDRITE_KEY" ]]; then
    success "Dendrite signing key already exists, skipping"
  else
    info "Generating Dendrite Matrix signing key..."
    docker run --rm \
      -v "$ROOT_DIR/data/dendrite-keys:/keys" \
      ghcr.io/element-hq/dendrite:latest \
      /usr/bin/generate-keys --private-key /keys/matrix_key.pem
    success "Dendrite signing key written to data/dendrite-keys/matrix_key.pem"
  fi
else
  info "communication scope not enabled — skipping Dendrite key generation"
fi

# ── Traefik .htpasswd check ────────────────────────────────────────────────────
section "Traefik .htpasswd"
HTPASSWD_FILE="$ROOT_DIR/core/config/traefik/dynamic/.htpasswd"
info "Checking Traefik dashboard .htpasswd"
if grep -q "PLACEHOLDER_REPLACE" "$HTPASSWD_FILE" 2>/dev/null; then
  warn ".htpasswd still contains placeholder — run 'make setup' or replace it manually:"
  warn "  htpasswd -nB admin | sed 's/\\\$/\\\$\\\$/g' > core/config/traefik/dynamic/.htpasswd"
else
  success ".htpasswd looks configured"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
success "Bootstrap complete. Enabled scopes: ${SCOPES[*]}"
echo ""
echo "  Start services with scope-specific make targets:"
echo ""
scope_enabled "network"       && echo "    make scope-network        — Traefik, Step CA, DNS, WireGuard" || true
scope_enabled "identity"      && echo "    make scope-identity       — Authentik SSO / OIDC" || true
scope_enabled "dev"           && echo "    make scope-dev            — Forgejo + Woodpecker CI" || true
scope_enabled "productivity"  && echo "    make scope-productivity   — SFTPGo, Stalwart, Radicale" || true
scope_enabled "communication" && echo "    make scope-communication  — Dendrite + Element Web" || true
scope_enabled "observability" && echo "    make scope-observability  — Prometheus + Loki + Grafana" || true
echo ""
echo "  Or start all enabled scopes in dependency order:"
echo "    make scope-all"
echo ""
echo "  After services are running:"
echo "    make configure-oidc — Fill in post-UI OIDC tokens"
echo "    make scope-status   — Check health of all running scopes"
