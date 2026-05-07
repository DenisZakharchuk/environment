# scopes/communication.sh — Team communication scope
# Matrix Dendrite homeserver + Element Web client

SCOPE_NAME="communication"
SCOPE_DESCRIPTION="Matrix chat (Dendrite homeserver) + Element Web client"
SCOPE_DEPENDS_ON="network"
SCOPE_SOFT_DEPENDS_ON="identity"

SCOPE_COMPOSE_DIRS="messenger"

SCOPE_VARS_PASSWORDS="DENDRITE_POSTGRES_PASSWORD"
SCOPE_VARS_GENERATED=""
SCOPE_VARS_CONFIG="MATRIX_SERVER_NAME"
SCOPE_VARS_COMPUTED=""
SCOPE_VARS_POST_UI=""

SCOPE_DATA_DIRS="dendrite-postgres dendrite-media dendrite-keys"

# Dendrite Matrix signing key must be generated before first start
SCOPE_INIT_TASKS="init_dendrite_key"

SCOPE_HEALTH_CHECK='curl -sf --max-time 5 -o /dev/null https://matrix.${DOMAIN}/_matrix/client/versions 2>/dev/null'
SCOPE_HEALTH_DESC="Dendrite responds at https://matrix.\${DOMAIN}/_matrix/client/versions"
