ROOT_DIR := $(shell pwd)
COMPOSE := docker compose

.PHONY: help init core identity vpn git files mail calendar messenger monitoring up-all down-all ps logs

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

init: ## Bootstrap: create Docker network, data dirs, init Step CA
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
up-all: core identity vpn git files mail calendar messenger monitoring ## Start all services in order

down-all: ## Stop all services
	@for svc in messenger calendar mail files git vpn identity core monitoring; do \
		$(COMPOSE) -f $$svc/docker-compose.yml down 2>/dev/null || true; \
	done

ps: ## Show running containers
	@docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

logs: ## Tail logs for a service: make logs SVC=core
	$(COMPOSE) -f $(SVC)/docker-compose.yml logs -f
