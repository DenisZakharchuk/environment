# scopes/dev.sh — Development tooling scope
# Forgejo (Git hosting) + Woodpecker CI

SCOPE_NAME="dev"
SCOPE_DESCRIPTION="Git hosting (Forgejo) + CI/CD pipelines (Woodpecker)"
SCOPE_DEPENDS_ON="network"
# identity is a soft dependency: Forgejo/Woodpecker work without SSO,
# but OIDC integration is available if identity scope is also enabled.
SCOPE_SOFT_DEPENDS_ON="identity"

SCOPE_COMPOSE_DIRS="git"

SCOPE_VARS_PASSWORDS="FORGEJO_POSTGRES_PASSWORD"
SCOPE_VARS_GENERATED="WOODPECKER_AGENT_SECRET"
SCOPE_VARS_CONFIG="WOODPECKER_ADMIN"
SCOPE_VARS_COMPUTED=""
SCOPE_VARS_POST_UI="WOODPECKER_FORGEJO_CLIENT WOODPECKER_FORGEJO_SECRET FORGEJO_ADMIN_TOKEN"

SCOPE_DATA_DIRS="forgejo forgejo-postgres woodpecker"

SCOPE_INIT_TASKS=""

SCOPE_HEALTH_CHECK='curl -sf --max-time 5 -o /dev/null https://git.${DOMAIN} 2>/dev/null'
SCOPE_HEALTH_DESC="Forgejo responds at https://git.\${DOMAIN}"
