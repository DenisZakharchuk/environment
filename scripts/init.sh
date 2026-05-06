#!/usr/bin/env bash
# scripts/init.sh — Bootstrap the infrastructure
# Run once before starting any services: bash scripts/init.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Load .env ──────────────────────────────────────────────────────────────────
if [[ ! -f "$ROOT_DIR/.env" ]]; then
  echo "ERROR: .env not found. Copy .env.example → .env and fill in values."
  exit 1
fi
# shellcheck source=/dev/null
source "$ROOT_DIR/.env"

echo "==> Creating shared Docker network: infra_net"
docker network create infra_net 2>/dev/null || echo "    infra_net already exists"

echo "==> Creating data directories"
dirs=(
  "$ROOT_DIR/data/step-ca"
  "$ROOT_DIR/data/traefik"
  "$ROOT_DIR/data/technitium"
  "$ROOT_DIR/data/authentik-postgres"
  "$ROOT_DIR/data/authentik-media"
  "$ROOT_DIR/data/authentik-certs"
  "$ROOT_DIR/data/authentik-redis"
  "$ROOT_DIR/data/wireguard"
  "$ROOT_DIR/data/forgejo"
  "$ROOT_DIR/data/forgejo-postgres"
  "$ROOT_DIR/data/woodpecker"
  "$ROOT_DIR/data/sftpgo"
  "$ROOT_DIR/data/stalwart"
  "$ROOT_DIR/data/radicale"
  "$ROOT_DIR/data/dendrite-postgres"
  "$ROOT_DIR/data/dendrite-media"
  "$ROOT_DIR/data/prometheus"
  "$ROOT_DIR/data/grafana"
  "$ROOT_DIR/data/loki"
)
for d in "${dirs[@]}"; do
  mkdir -p "$d"
done

echo "==> Initializing Step CA"
if [[ -f "$ROOT_DIR/data/step-ca/config/ca.json" ]]; then
  echo "    Step CA already initialized, skipping."
else
  # Initialize CA inside a temporary container
  docker run --rm -it \
    -v "$ROOT_DIR/data/step-ca:/home/step" \
    -e DOCKER_STEPCA_INIT_NAME="Infra Local CA" \
    -e DOCKER_STEPCA_INIT_DNS_NAMES="ca.${DOMAIN},localhost" \
    -e DOCKER_STEPCA_INIT_PROVISIONER_NAME="admin" \
    -e DOCKER_STEPCA_INIT_ADDRESS=":9000" \
    -e DOCKER_STEPCA_INIT_ACME=true \
    smallstep/step-ca:latest /bin/sh -c "step ca init --acme"

  echo ""
  echo "    Step CA initialized. Reading fingerprint..."
  FINGERPRINT=$(docker run --rm \
    -v "$ROOT_DIR/data/step-ca:/home/step" \
    smallstep/step-ca:latest \
    step certificate fingerprint /home/step/certs/root_ca.crt 2>/dev/null || true)

  if [[ -n "$FINGERPRINT" ]]; then
    # Write fingerprint into .env
    if grep -q "^STEP_CA_FINGERPRINT=" "$ROOT_DIR/.env"; then
      sed -i "s|^STEP_CA_FINGERPRINT=.*|STEP_CA_FINGERPRINT=${FINGERPRINT}|" "$ROOT_DIR/.env"
    else
      echo "STEP_CA_FINGERPRINT=${FINGERPRINT}" >> "$ROOT_DIR/.env"
    fi
    echo "    Fingerprint saved to .env: ${FINGERPRINT}"
  fi
fi

echo ""
echo "==> Bootstrap complete. Next steps:"
echo "    1. Review .env and fill in any remaining passwords."
echo "    2. make core      — Start Traefik, Step CA, Technitium DNS"
echo "    3. make identity  — Start Authentik"
echo "    4. make <service> — Start individual services"
echo "    5. Run 'make help' for all available targets."
