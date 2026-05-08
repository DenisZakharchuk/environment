ROOT_DIR := $(shell pwd)
COMPOSE := docker compose

.PHONY: help setup init configure-oidc status ps logs \
        network-up network-down network-purge \
        identity-up identity-down identity-purge \
        dev-up dev-down dev-purge \
        productivity-up productivity-down productivity-purge \
        communication-up communication-down communication-purge \
        observability-up observability-down observability-purge \
        up down purge purge-full

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

setup: ## Interactive setup wizard: prompts for passwords, generates secrets, writes .env, calls init
	@bash scripts/setup.sh

configure-oidc: ## Fill in post-UI OIDC tokens (run after services are up)
	@bash scripts/configure-oidc.sh

init: ## Non-interactive bootstrap: Docker network, data dirs, Step CA (requires .env from 'make setup')
	@bash scripts/init.sh

# ── Scope lifecycle (noun-verb: scope name first, action second) ──────────────
# Each scope provides -up, -down, and -purge actions.
# All metadata (compose dirs, data dirs, deps) lives in scopes/<name>.sh —
# adding a new scope requires only a new scope file + 3 lines below.

network-up: ## Start network scope: Traefik, Step CA, DNS, WireGuard
	@bash scripts/scope.sh network up

network-down: ## Stop network scope
	@bash scripts/scope.sh network down

network-purge: ## Purge network scope: stop containers, remove volumes, wipe data
	@bash scripts/scope.sh network purge

identity-up: ## Start identity scope: Authentik SSO/OIDC (requires: network)
	@bash scripts/scope.sh identity up

identity-down: ## Stop identity scope
	@bash scripts/scope.sh identity down

identity-purge: ## Purge identity scope
	@bash scripts/scope.sh identity purge

dev-up: ## Start dev scope: Forgejo + Woodpecker CI
	@bash scripts/scope.sh dev up

dev-down: ## Stop dev scope
	@bash scripts/scope.sh dev down

dev-purge: ## Purge dev scope
	@bash scripts/scope.sh dev purge

productivity-up: ## Start productivity scope: SFTPGo, Stalwart, Radicale
	@bash scripts/scope.sh productivity up

productivity-down: ## Stop productivity scope
	@bash scripts/scope.sh productivity down

productivity-purge: ## Purge productivity scope
	@bash scripts/scope.sh productivity purge

communication-up: ## Start communication scope: Dendrite + Element Web
	@bash scripts/scope.sh communication up

communication-down: ## Stop communication scope
	@bash scripts/scope.sh communication down

communication-purge: ## Purge communication scope
	@bash scripts/scope.sh communication purge

observability-up: ## Start observability scope: Prometheus + Loki + Grafana
	@bash scripts/scope.sh observability up

observability-down: ## Stop observability scope
	@bash scripts/scope.sh observability down

observability-purge: ## Purge observability scope
	@bash scripts/scope.sh observability purge

# ── Aggregate lifecycle ────────────────────────────────────────────────────────
up: ## Start all scopes in ENABLED_SCOPES (.env) in dependency order
	@bash scripts/scope.sh all up

down: ## Stop all known scopes in reverse dependency order
	@bash scripts/scope.sh all down

purge: ## Purge all scopes: stop containers, remove volumes, wipe all data (keeps .env)
	@bash scripts/scope.sh all purge

purge-full: ## Full factory reset: purge all scopes + delete .env and .htpasswd
	@bash scripts/scope.sh all purge --full

# ── Helpers ────────────────────────────────────────────────────────────────────
status: ## Show live health status of all enabled scopes
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

ps: ## Show running containers
	@docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

logs: ## Tail logs for a service dir: make logs SVC=core
	$(COMPOSE) -f $(SVC)/docker-compose.yml logs -f
