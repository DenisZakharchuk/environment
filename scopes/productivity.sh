# scopes/productivity.sh — Productivity services scope
# File sharing (SFTPGo) + Mail (Stalwart) + Calendar/Contacts (Radicale)
#
# NOTE: Radicale uses Authentik forward-auth middleware (hard dependency on identity).
# If identity scope is NOT enabled, calendar will not function correctly.
# setup.sh will warn about this constraint.

SCOPE_NAME="productivity"
SCOPE_DESCRIPTION="File sharing (SFTPGo), mail (Stalwart), calendar/contacts (Radicale)"
SCOPE_DEPENDS_ON="network"
# identity is effectively hard for calendar (Radicale forward-auth),
# and soft for files (SFTPGo OIDC optional) and mail (standalone).
# Treated as soft at scope level; setup.sh issues a specific warning for calendar.
SCOPE_SOFT_DEPENDS_ON="identity"

SCOPE_COMPOSE_DIRS="files mail calendar"

SCOPE_VARS_PASSWORDS="SFTPGO_ADMIN_PASSWORD STALWART_ADMIN_PASSWORD"
SCOPE_VARS_GENERATED=""
SCOPE_VARS_CONFIG=""
SCOPE_VARS_COMPUTED=""
SCOPE_VARS_POST_UI="SFTPGO_OIDC_CLIENT_ID SFTPGO_OIDC_CLIENT_SECRET"

SCOPE_DATA_DIRS="sftpgo stalwart radicale"

SCOPE_INIT_TASKS=""

# Check SFTPGo as the representative health endpoint
SCOPE_HEALTH_CHECK='curl -sf --max-time 5 -o /dev/null https://files.${DOMAIN} 2>/dev/null'
SCOPE_HEALTH_DESC="SFTPGo responds at https://files.\${DOMAIN}"
