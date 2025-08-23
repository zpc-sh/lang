.PHONY: help setup test compile-nifs deploy deploy-quick deploy-initial rollback logs ssh console migrate stripe-listen clean

# Default target
help:
	@echo "LANG Development & Deployment Commands"
	@echo "======================================"
	@echo ""
	@echo "Development:"
	@echo "  make setup          - Initial project setup"
	@echo "  make test           - Run tests"
	@echo "  make compile-nifs   - Compile Rust NIFs"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make precommit      - Run pre-commit checks"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-initial - First-time production deployment"
	@echo "  make deploy         - Regular deployment with full checks"
	@echo "  make deploy-quick   - Quick deployment without tests"
	@echo "  make rollback       - Rollback to previous version"
	@echo ""
	@echo "Production Management:"
	@echo "  make logs           - View application logs"
	@echo "  make ssh            - SSH into production instance"
	@echo "  make console        - Open Elixir console in production"
	@echo "  make migrate        - Run database migrations"
	@echo "  make status         - Show application status"
	@echo ""
	@echo "Development Tools:"
	@echo "  make stripe-listen  - Listen to Stripe webhooks locally"
	@echo "  make dev-server     - Start development server"
	@echo "  make format         - Format code"
	@echo "  make lint           - Run code linting"

# Development commands
setup:
	@echo "🔧 Setting up LANG development environment..."
	mix deps.get
	mix ecto.setup
	mix assets.setup
	mix assets.build
	mix rustler.compile
	@echo "✅ Setup complete!"

test:
	@echo "🧪 Running tests..."
	mix test

compile-nifs:
	@echo "🦀 Compiling Rust NIFs..."
	mix rustler.compile

clean:
	@echo "🧹 Cleaning build artifacts..."
	mix clean
	mix rustler.clean
	rm -rf _build
	rm -rf deps
	rm -rf assets/node_modules

precommit:
	@echo "🔍 Running pre-commit checks..."
	mix format --check-formatted
	mix credo --strict
	mix test
	mix rustler.compile

# Deployment commands
deploy-initial:
	@echo "🚀 Initial production deployment..."
	@if [ ! -f ".env.production" ]; then \
		echo "❌ .env.production file not found"; \
		echo "Please create it from .env.production.template"; \
		exit 1; \
	fi
	@source .env.production && ./scripts/deploy_initial.sh

deploy:
	@echo "🚀 Deploying LANG to production..."
	./scripts/deploy_update.sh deploy

deploy-quick:
	@echo "⚡ Quick deployment (no tests)..."
	./scripts/deploy_update.sh quick

rollback:
	@echo "⏪ Rolling back deployment..."
	./scripts/deploy_update.sh rollback

# Production management
logs:
	@echo "📋 Viewing application logs..."
	fly logs

ssh:
	@echo "🔐 Connecting to production instance..."
	fly ssh console

console:
	@echo "💻 Opening Elixir console in production..."
	fly ssh console -C "./bin/lang remote"

migrate:
	@echo "🗄️  Running database migrations..."
	fly ssh console -C "./bin/lang eval Lang.Release.migrate"

status:
	@echo "📊 Application status..."
	fly status

# Development tools
stripe-listen:
	@echo "🎧 Listening for Stripe webhooks..."
	stripe listen --forward-to localhost:4000/webhooks/stripe

dev-server:
	@echo "🔥 Starting development server..."
	mix phx.server

format:
	@echo "📝 Formatting code..."
	mix format

lint:
	@echo "🔍 Running code linting..."
	mix credo

# Health checks
health:
	@echo "🏥 Checking application health..."
	curl -f https://lang.nocsi.com/health || echo "❌ Health check failed"

health-local:
	@echo "🏥 Checking local application health..."
	curl -f http://localhost:4000/health || echo "❌ Local health check failed"

# Asset management
assets-setup:
	@echo "📦 Setting up assets..."
	mix assets.setup

assets-build:
	@echo "🔨 Building assets..."
	mix assets.build

assets-deploy:
	@echo "🚀 Deploying assets..."
	mix assets.deploy

# Database commands
db-setup:
	@echo "🗄️  Setting up database..."
	mix ecto.setup

db-reset:
	@echo "♻️  Resetting database..."
	mix ecto.reset

db-migrate:
	@echo "➡️  Running migrations..."
	mix ecto.migrate

db-rollback:
	@echo "⬅️  Rolling back migration..."
	mix ecto.rollback

# Release commands
release-build:
	@echo "📦 Building release..."
	MIX_ENV=prod mix release

release-test:
	@echo "🧪 Testing release..."
	MIX_ENV=prod mix test

# Security commands
security-check:
	@echo "🔒 Running security checks..."
	mix sobelow

deps-audit:
	@echo "🔍 Auditing dependencies..."
	mix deps.audit

# Monitoring commands
metrics:
	@echo "📈 Viewing metrics..."
	curl -s https://lang.nocsi.com/metrics || echo "❌ Metrics not available"

# Backup commands
backup-db:
	@echo "💾 Creating database backup..."
	@if [ -z "$(DATABASE_URL)" ]; then \
		echo "❌ DATABASE_URL not set"; \
		exit 1; \
	fi
	pg_dump $(DATABASE_URL) > backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "✅ Database backup created"

# Environment setup
env-check:
	@echo "🔧 Checking environment configuration..."
	@if [ ! -f ".env.production" ]; then \
		echo "❌ .env.production not found"; \
		echo "Copy from .env.production.template and fill in values"; \
	else \
		echo "✅ .env.production exists"; \
	fi
	@if command -v fly >/dev/null 2>&1; then \
		echo "✅ Fly CLI installed"; \
	else \
		echo "❌ Fly CLI not installed"; \
	fi
	@if command -v mix >/dev/null 2>&1; then \
		echo "✅ Elixir/Mix available"; \
	else \
		echo "❌ Elixir/Mix not available"; \
	fi
	@if command -v cargo >/dev/null 2>&1; then \
		echo "✅ Rust/Cargo available"; \
	else \
		echo "❌ Rust/Cargo not available (required for NIFs)"; \
	fi

# Make scripts executable
make-scripts-executable:
	@echo "🔧 Making scripts executable..."
	chmod +x scripts/*.sh
	@echo "✅ Scripts are now executable"