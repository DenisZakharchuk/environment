# scopes/identity.sh — Identity and SSO scope
# Authentik: OIDC provider, SSO, forward auth, user management

SCOPE_NAME="identity"
SCOPE_DESCRIPTION="SSO / OIDC provider (Authentik) — required for centralised login"
SCOPE_DEPENDS_ON="network"

SCOPE_COMPOSE_DIRS="identity"

SCOPE_VARS_PASSWORDS="AUTHENTIK_POSTGRES_PASSWORD"
SCOPE_VARS_GENERATED="AUTHENTIK_SECRET_KEY"
SCOPE_VARS_CONFIG=""
SCOPE_VARS_COMPUTED=""
SCOPE_VARS_POST_UI="AUTHENTIK_OUTPOST_TOKEN"

SCOPE_DATA_DIRS="authentik-postgres authentik-media authentik-certs authentik-redis"

SCOPE_INIT_TASKS=""

SCOPE_HEALTH_CHECK='curl -sf --max-time 5 -o /dev/null https://auth.${DOMAIN}/api/v3/ 2>/dev/null'
SCOPE_HEALTH_DESC="Authentik API responds at https://auth.\${DOMAIN}/api/v3/"
