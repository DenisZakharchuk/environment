# scopes/observability.sh — Monitoring and logging scope
# Prometheus (metrics) + Loki + Promtail (logs) + Grafana (dashboards)

SCOPE_NAME="observability"
SCOPE_DESCRIPTION="Metrics (Prometheus), logs (Loki), dashboards (Grafana)"
SCOPE_DEPENDS_ON="network"
SCOPE_SOFT_DEPENDS_ON="identity"

SCOPE_COMPOSE_DIRS="monitoring"

SCOPE_VARS_PASSWORDS="GRAFANA_ADMIN_PASSWORD"
SCOPE_VARS_GENERATED=""
SCOPE_VARS_CONFIG=""
SCOPE_VARS_COMPUTED=""
SCOPE_VARS_POST_UI="GRAFANA_OIDC_CLIENT_ID GRAFANA_OIDC_CLIENT_SECRET"

SCOPE_DATA_DIRS="prometheus grafana loki"

SCOPE_INIT_TASKS=""

SCOPE_HEALTH_CHECK='curl -sf --max-time 5 -o /dev/null https://grafana.${DOMAIN}/api/health 2>/dev/null'
SCOPE_HEALTH_DESC="Grafana responds at https://grafana.\${DOMAIN}/api/health"
