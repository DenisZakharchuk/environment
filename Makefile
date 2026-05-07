ROOT_DIR := $(shell pwd)
COMPOSE := docker compose

.PHONY: help setup init configure-oidc \
        core core-down identity identity-down vpn vpn-down git git-down \
        files files-down mail mail-down calendar calendar-down \
        messenger messenger-down monitoring monitoring-down \
        up-all down-all ps logs \
        scope-network scope-network-down \
        scope-identity scope-identity-down \
        scope-dev scope-dev-down \
        scope-productivity scope-productivity-down \
        scope-communication scope-communication-down \
        scope-observability scope-observability-down \
        scope-all scope-down-all scope-status

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## Interactive setup wizard: prompts for passwords, generates secrets, writes .env, calls init
	@bash scripts/setup.sh

configure-oidc: ## Fill in post-UI OIDC tokens (run after services are up)
	@bash scripts/configure-oidc.sh

init: ## Non-interactive bootstrap: Docker network, data dirs, Step CA (requires .env from 'make setup')
	@bash scripts/init.sh

# ── Core (must start first) ───────────────────────────────────────────────────
core: ## Start core infrastructure: Traefik, Step CA, Technitium DNS
	$(COMPOSE) -f core/docker-compose.yml --env-file .env up -d

core-down: ## Stop core infrastructure
	$(COMPOSE) -f core/docker-compose.yml down

# ── Identity (start after core) ───────────────────────────────────────────────
identity: ## Start identity provider: Authentik + PostgreSQL + Redis
	$(COMPOSE) -f identity/docker-compose.yml --env-file .env up -d

identity-down: ## Stop identity provider
	$(COMPOSE) -f identity/docker-compose.yml down

# ── VPN ───────────────────────────────────────────────────────────────────────
vpn: ## Start VPN: WireGuard Easy
	$(COMPOSE) -f vpn/docker-compose.yml --env-file .env up -d

vpn-down: ## Stop VPN
	$(COMPOSE) -f vpn/docker-compose.yml down

# ── Git ───────────────────────────────────────────────────────────────────────
git: ## Start Git hosting: Forgejo + Woodpecker CI
	$(COMPOSE) -f git/docker-compose.yml --env-file .env up -d

git-down: ## Stop Git hosting
	$(COMPOSE) -f git/docker-compose.yml down

# ── File sharing ──────────────────────────────────────────────────────────────
files: ## Start file sharing: SFTPGo
	$(COMPOSE) -f files/docker-compose.yml --env-file .env up -d

files-down: ## Stop file sharing
	$(COMPOSE) -f files/docker-compose.yml down

# ── Mail ──────────────────────────────────────────────────────────────────────
mail: ## Start mail server: Stalwart Mail
	$(COMPOSE) -f mail/docker-compose.yml --env-file .env up -d

mail-down: ## Stop mail server
	$(COMPOSE) -f mail/docker-compose.yml down

# ── Calendar ──────────────────────────────────────────────────────────────────
calendar: ## Start calendar/contacts: Radicale (CalDAV/CardDAV)
	$(COMPOSE) -f calendar/docker-compose.yml --env-file .env up -d

calendar-down: ## Stop calendar
	$(COMPOSE) -f calendar/docker-compose.yml down

# ── Messenger ─────────────────────────────────────────────────────────────────
messenger: ## Start messenger: Matrix Dendrite + Element Web
	$(COMPOSE) -f messenger/docker-compose.yml --env-file .env up -d

messenger-down: ## Stop messenger
	$(COMPOSE) -f messenger/docker-compose.yml down

# ── Monitoring ────────────────────────────────────────────────────────────────
monitoring: ## Start monitoring: Prometheus + Grafana + Loki
	$(COMPOSE) -f monitoring/docker-compose.yml --env-file .env up -d

monitoring-down: ## Stop monitoring
	$(COMPOSE) -f monitoring/docker-compose.yml down

# ── Lifecycle helpers ─────────────────────────────────────────────────────────
up-all: core identity vpn git files mail calendar messenger monitoring ## Start all services in order (see also: scope-all)

down-all: ## Stop all services
	@for svc in messenger calendar mail files git vpn identity core monitoring; do \
		$(COMPOSE) -f $$svc/docker-compose.yml down 2>/dev/null || true; \
	done

ps: ## Show running containers
	@docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

logs: ## Tail logs for a service: make logs SVC=core
	$(COMPOSE) -f $(SVC)/docker-compose.yml logs -f

# ── Scope-based deployment ─────────────────────────────────────────────────────
# Scope targets check hard dependencies before starting services.
# Preferred over individual targets — respects dependency order.
# Start all enabled scopes at once with: make scope-all

scope-network: ## Start network scope: Traefik, Step CA, Technitium DNS, WireGuard
	$(COMPOSE) -f core/docker-compose.yml --env-file .env up -d
	$(COMPOSE) -f vpn/docker-compose.yml  --env-file .env up -d

scope-network-down: ## Stop network scope
	$(COMPOSE) -f vpn/docker-compose.yml  down
	$(COMPOSE) -f core/docker-compose.yml down

scope-identity: ## Start identity scope: Authentik SSO/OIDC (requires: network)
	@bash scripts/check-scope-deps.sh identity
	$(COMPOSE) -f identity/docker-compose.yml --env-file .env up -d

scope-identity-down: ## Stop identity scope
	$(COMPOSE) -f identity/docker-compose.yml down

scope-dev: ## Start dev scope: Forgejo + Woodpecker CI (requires: network; soft: identity)
	@bash scripts/check-scope-deps.sh dev --soft
	$(COMPOSE) -f git/docker-compose.yml --env-file .env up -d

scope-dev-down: ## Stop dev scope
	$(COMPOSE) -f git/docker-compose.yml down

scope-productivity: ## Start productivity scope: SFTPGo, Stalwart, Radicale (requires: network; soft: identity)
	@bash scripts/check-scope-deps.sh productivity --soft
	$(COMPOSE) -f files/docker-compose.yml    --env-file .env up -d
	$(COMPOSE) -f mail/docker-compose.yml     --env-file .env up -d
	$(COMPOSE) -f calendar/docker-compose.yml --env-file .env up -d

scope-productivity-down: ## Stop productivity scope
	$(COMPOSE) -f calendar/docker-compose.yml down
	$(COMPOSE) -f mail/docker-compose.yml     down
	$(COMPOSE) -f files/docker-compose.yml    down

scope-communication: ## Start communication scope: Dendrite + Element Web (requires: network; soft: identity)
	@bash scripts/check-scope-deps.sh communication --soft
	$(COMPOSE) -f messenger/docker-compose.yml --env-file .env up -d

scope-communication-down: ## Stop communication scope
	$(COMPOSE) -f messenger/docker-compose.yml down

scope-observability: ## Start observability scope: Prometheus + Loki + Grafana (requires: network; soft: identity)
	@bash scripts/check-scope-deps.sh observability --soft
	$(COMPOSE) -f monitoring/docker-compose.yml --env-file .env up -d

scope-observability-down: ## Stop observability scope
	$(COMPOSE) -f monitoring/docker-compose.yml down

scope-all: ## Start all scopes listed in ENABLED_SCOPES (.env) in dependency order
	@set -a && . .env && set +a; \
	for scope in $$ENABLED_SCOPES; do \
		echo ""; \
		echo "==> Starting scope: $$scope"; \
		$(MAKE) --no-print-directory scope-$$scope || exit 1; \
	done

scope-down-all: ## Stop all scopes in reverse order
	@set -a && . .env && set +a; \
	reversed=""; \
	for s in $$ENABLED_SCOPES; do reversed="$$s $$reversed"; done; \
	for scope in $$reversed; do \
		echo "==> Stopping scope: $$scope"; \
		$(MAKE) --no-print-directory scope-$$scope-down 2>/dev/null || true; \
	done

scope-status: ## Show live health status of all enabled scopes
	@set -a && . .env && set +a; \
	echo ""; \
	echo "Scope health status (DOMAIN=$$DOMAIN):"; \
	echo ""; \
	for scope in $$ENABLED_SCOPES; do \
		. scopes/$$scope.sh 2>/dev/null; \
		if eval "$$SCOPE_HEALTH_CHECK" 2>/dev/null; then \
			printf "  \033[32m✓\033[0m %-18s %s\n" "$$scope" "$$SCOPE_HEALTH_DESC"; \
		else \
			printf "  \033[31m✗\033[0m %-18s NOT REACHABLE\n" "$$scope"; \
		fi; \
	done; \
	echo ""
