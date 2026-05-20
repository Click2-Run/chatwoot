# Variables
APP_NAME := chatwoot
RAILS_ENV ?= development

# Docker image settings — single source of truth read by build/build.sh.
# Override at the command line with: make image IMAGE_TAG=20260514.1
DOCKER_REGISTRY := click2run
IMAGE_NAME := multicanal
IMAGE_TAG := $(shell date -u +%Y%m%d)

# Targets
setup:
	gem install bundler
	bundle install
	pnpm install

db_create:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:create

db_migrate:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:migrate

db_seed:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:seed

db_reset:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:reset

db:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:chatwoot_prepare

console:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails console

server:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails server -b 0.0.0.0 -p 3000

burn:
	bundle && pnpm install

run:
	@if [ -f ./.overmind.sock ]; then \
		echo "Overmind is already running. Use 'make force_run' to start a new instance."; \
	else \
		overmind start -f Procfile.dev; \
	fi

force_run:
	@echo "Cleaning up Overmind processes..."
	@lsof -ti:3036 2>/dev/null | xargs kill -9 2>/dev/null || true
	@lsof -ti:3000 2>/dev/null | xargs kill -9 2>/dev/null || true
	@rm -f ./.overmind.sock
	@rm -f tmp/pids/*.pid
	@echo "Cleanup complete"
	overmind start -f Procfile.dev

force_run_tunnel:
	lsof -ti:3000 | xargs kill -9 2>/dev/null || true
	rm -f ./.overmind.sock
	rm -f tmp/pids/*.pid
	overmind start -f Procfile.tunnel

debug:
	overmind connect backend

debug_worker:
	overmind connect worker

docker:
	docker build -t $(APP_NAME) -f ./docker/Dockerfile .

# ---------------------------------------------------------------------------
# Production image — click2run/multicanal:<date>
# ---------------------------------------------------------------------------
# Delegates to build/build.sh (native multi-arch via SSH'd cluster nodes).
# See `./build/build.sh --help` for the full option list.

image:
	./build/build.sh --tag $(IMAGE_TAG)

image_local:
	./build/build.sh --local --no-push --tag $(IMAGE_TAG)

image_push:
	./build/build.sh --push --tag $(IMAGE_TAG)

image_amd64:
	./build/build.sh --platform amd64 --tag $(IMAGE_TAG)

image_arm64:
	./build/build.sh --platform arm64 --tag $(IMAGE_TAG)

image_clean:
	./build/build.sh --no-cache --cleanup --tag $(IMAGE_TAG)

.PHONY: setup db_create db_migrate db_seed db_reset db console server burn docker run force_run force_run_tunnel debug debug_worker image image_local image_push image_amd64 image_arm64 image_clean
