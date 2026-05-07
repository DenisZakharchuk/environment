# scopes/network.sh — Network foundation scope
# VPN perimeter + DNS + internal CA + ingress proxy
# This scope MUST be started before all others.

SCOPE_NAME="network"
SCOPE_DESCRIPTION="VPN perimeter, DNS, internal CA (Step CA), Traefik ingress"
SCOPE_DEPENDS_ON=""
SCOPE_COMPOSE_DIRS="core vpn"

# Variables prompted during setup
SCOPE_VARS_PASSWORDS="TRAEFIK_DASHBOARD_PASSWORD TECHNITIUM_ADMIN_PASSWORD WG_PASSWORD"
# Variables auto-generated (not prompted)
SCOPE_VARS_GENERATED="WG_PASSWORD_HASH"
# Variables derived/typed by user (not passwords)
SCOPE_VARS_CONFIG="DOMAIN HOST_IP"
# Variables set after init.sh runs
SCOPE_VARS_COMPUTED="STEP_CA_FINGERPRINT"
# Variables filled after UI (configure-oidc)
SCOPE_VARS_POST_UI=""

# Data directories needed by this scope
SCOPE_DATA_DIRS="step-ca traefik technitium wireguard"

# Init tasks run by init.sh for this scope (function names in scripts/init.sh)
SCOPE_INIT_TASKS="init_docker_network init_step_ca init_traefik_htpasswd"

# Health check: verifies this scope is actually up and reachable
# Evaluated after variable substitution — uses $DOMAIN and $HOST_IP from .env
SCOPE_HEALTH_CHECK='curl -sf --max-time 5 -o /dev/null https://traefik.${DOMAIN}/ping 2>/dev/null'

# Human-readable check description (shown in scope-status output)
SCOPE_HEALTH_DESC="Traefik responds at https://traefik.\${DOMAIN}/ping"
