# 🛠️ LANG Quick Commands Reference

**Last Updated:** January 2025  
**Purpose:** Quick copy-paste commands for common LANG development and deployment tasks

---

## 🚀 Getting Started

### Initial Setup
```bash
# Clone and enter project
cd lang

# Install dependencies
mix deps.get
npm install --prefix assets

# Setup database
mix ecto.setup

# Compile native Rust NIFs
mix compile.native

# Run tests
mix test
```

---

## 🔧 Development Commands

### Start Development Server
```bash
# Standard server (CAUTION: runs indefinitely, use Ctrl+C to stop)
mix phx.server

# Interactive shell with server
iex -S mix phx.server

# Just compile without starting server
mix compile
```

### Database Operations
```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Generate new Ash migrations
mix ash_postgres.generate_migrations --name my_migration_name

# Check migration status
mix ecto.migrations
```

### Testing
```bash
# Run all tests
mix test

# Run specific test file
mix test test/lang/accounts_test.exs

# Run specific test by line number
mix test test/lang/accounts_test.exs:42

# Run only failed tests
mix test --failed

# Run with coverage report
mix test --cover

# Run tests with maximum 5 failures
mix test --max-failures 5

# Watch mode (run tests on file change)
mix test.watch
```

### Code Quality
```bash
# Run all pre-commit checks
mix precommit

# Compile with warnings as errors
mix compile --warnings-as-errors

# Format code
mix format

# Run Credo (code analysis)
mix credo --strict

# Run Dialyzer (type checking)
mix dialyzer

# Check for unused dependencies
mix deps.unlock --check-unused
```

---

## 🦀 Native Rust NIFs

### Compilation
```bash
# Compile native extensions
mix compile.native

# Clean native build artifacts
mix clean.native

# Rebuild from scratch
mix clean.native && mix compile.native

# Check Rust version
rustc --version
```

### Testing NIFs in IEx
```bash
iex -S mix

# Test filesystem scanner
Lang.Native.FSScanner.scan("./", max_depth: 3)
Lang.Native.FSScanner.search("./lib", "TODO|FIXME")
Lang.Native.FSScanner.preview("README.md", max_lines: 20)

# Test performance engine
Lang.Native.PerfEngine.analyze_text("# Hello World", format: :markdown)
```

---

## 🔐 Security & Secrets

### Generate Secrets
```bash
# Phoenix secret key (128 characters)
mix phx.gen.secret

# Shorter secret (32 characters) - for salts
mix phx.gen.secret 32

# Longer secret (64 characters) - for auth tokens
mix phx.gen.secret 64

# Encryption key (32 bytes, base64 encoded)
iex -S mix
:crypto.strong_rand_bytes(32) |> Base.encode64()
```

### Environment Setup
```bash
# Copy example environment file
cp .env.example .env

# Edit with your secrets (use your preferred editor)
nano .env
# or
vim .env
# or
code .env
```

---

## 🗄️ Ash Framework

### Ash Code Generation
```bash
# Generate migrations from Ash resources
mix ash_postgres.generate_migrations --name my_changes

# Check what would be generated (dry run)
mix ash_postgres.generate_migrations --check

# Run Ash codegen
mix ash.codegen
```

### Ash Resources in IEx
```bash
iex -S mix

# Read operations
alias Lang.Accounts.User
User.read_all!()
User.by_id!("user-id-here")
User.by_email!("test@example.com")

# Create operations
User.create!(%{name: "Test", email: "test@example.com"})

# Update operations
user = User.by_email!("test@example.com")
User.update!(user, %{name: "New Name"})

# Load associations
import Ash.Query
User.by_id!("user-id") |> Ash.Query.load([:organization, :api_keys])
```

---

## 🔨 Background Jobs (Oban)

### Oban Operations in IEx
```bash
iex -S mix

# Check Oban status
Oban.check_queue(queue: :default)

# View queue configuration
Oban.config()

# Cancel all jobs
Oban.cancel_all_jobs()

# Pause a queue
Oban.pause_queue(queue: :analysis)

# Resume a queue
Oban.resume_queue(queue: :analysis)

# Scale a queue
Oban.scale_queue(queue: :analysis, limit: 10)
```

### Queue Background Job
```bash
# In your application code
%{path: "/some/path", session_id: session_id}
|> Lang.Workers.FileSystemScanWorker.new(queue: :analysis)
|> Oban.insert()
```

---

## 🚀 Deployment (Fly.io)

### Initial Setup
```bash
# Install Fly CLI
curl -L https://fly.io/install.sh | sh

# Login to Fly.io
fly auth login

# Launch app (creates fly.toml)
fly launch --no-deploy

# Create PostgreSQL database
fly postgres create lang-db --region sjc

# Attach database to app
fly postgres attach lang-db
```

### Set Secrets
```bash
# Set individual secret
fly secrets set SECRET_KEY_BASE="your-secret-here"

# Set multiple secrets at once
fly secrets set \
  SECRET_KEY_BASE="..." \
  LIVE_VIEW_SIGNING_SALT="..." \
  ASH_AUTHENTICATION_SECRET="..." \
  ENCRYPTION_KEY="..." \
  ANTHROPIC_API_KEY="..." \
  OPENAI_API_KEY="..." \
  STRIPE_SECRET_KEY="..." \
  STRIPE_PUBLISHABLE_KEY="..." \
  STRIPE_WEBHOOK_SECRET="..."

# List all secrets (names only, not values)
fly secrets list

# Remove a secret
fly secrets unset SECRET_NAME
```

### Deploy
```bash
# Deploy application
fly deploy

# Deploy with specific Dockerfile
fly deploy --dockerfile Dockerfile

# Deploy without health checks
fly deploy --no-health-checks

# Deploy to specific region
fly deploy --region sjc
```

### Monitoring & Debugging
```bash
# Check app status
fly status

# View logs (real-time)
fly logs

# View logs (last 200 lines)
fly logs --lines 200

# Open app in browser
fly open

# Open Fly.io dashboard
fly dashboard

# SSH into running instance
fly ssh console

# Run command in SSH
fly ssh console -C "ls -la"
```

### Database Operations
```bash
# Connect to PostgreSQL
fly postgres connect -a lang-db

# Run migrations in production
fly ssh console -C "/app/bin/migrate"

# Open IEx console in production
fly ssh console -C "/app/bin/lang remote"

# Backup database
fly postgres backup create -a lang-db

# List backups
fly postgres backup list -a lang-db
```

### Scaling
```bash
# Scale to 2 instances
fly scale count 2

# Scale to specific regions
fly scale count 2 --region sjc,iad

# Scale memory
fly scale memory 512

# Scale VM size
fly scale vm shared-cpu-1x

# Auto-scale
fly autoscale set min=1 max=10
```

---

## 🧪 Testing & QA

### LSP Debug Harness
```bash
# Start LSP server with debug streaming
./scripts/start_lsp_debug.sh quick

# Full debug environment with web dashboard
./scripts/start_lsp_debug.sh full

# Connect to debug stream (in another terminal)
nc 127.0.0.1 4002

# Open web dashboard
open http://127.0.0.1:4004/
```

### Load Testing
```bash
# Run agent harness tests
mix test.agent_harness

# Run LSP comparison tests
mix test test/lang_web/live/testing/lsp_comparator_live_test.exs
```

---

## 📊 Monitoring & Analytics

### Check Application Health
```bash
# Local health check
curl http://localhost:4000/health

# Production health check
curl https://your-app.fly.dev/health

# Check specific endpoint
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://your-app.fly.dev/api/v1/status
```

### View Metrics
```bash
# In IEx
iex -S mix

# Check Oban metrics
Oban.check_queue(queue: :default)

# Check Ecto connection pool
Ecto.Adapters.SQL.query(Lang.Repo, "SELECT count(*) FROM users", [])

# Memory usage
:erlang.memory()

# Process count
length(Process.list())
```

---

## 🛠️ Maintenance

### Clean Up
```bash
# Clean build artifacts
mix clean

# Clean dependencies
mix deps.clean --all

# Clean native artifacts
mix clean.native

# Clean everything and rebuild
mix clean && mix clean.native && mix deps.get && mix compile

# Remove unused dependencies
mix deps.unlock --unused
mix deps.clean --unused
```

### Update Dependencies
```bash
# Check for outdated dependencies
mix hex.outdated

# Update all dependencies
mix deps.update --all

# Update specific dependency
mix deps.update phoenix

# Get dependencies
mix deps.get
```

---

## 🐛 Debugging

### IEx Debugging
```bash
# Start IEx with application
iex -S mix

# Reload module
r(ModuleName)

# Recompile
recompile()

# Get module info
ModuleName.__info__(:functions)

# Inspect with labels
IO.inspect(value, label: "Debug")

# Pretty print
IO.inspect(value, pretty: true, width: 80)
```

### Common Debug Patterns
```elixir
# In IEx
require IEx; IEx.pry()  # Set breakpoint (requires IEx.pry in code)

# Enable debug logging
Logger.configure(level: :debug)

# Trace function calls
:dbg.tracer()
:dbg.p(:all, :c)
:dbg.tpl(ModuleName, :function_name, :_)
```

---

## 📦 Git Operations

### Common Git Workflows
```bash
# Check status
git status

# Stage all changes
git add .

# Stage interactively
git add -p

# Commit with message
git commit -m "feat: add new feature"

# Push to remote
git push origin main

# Create new branch
git checkout -b feature/my-feature

# View commit history
git log --oneline --graph --all

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Clean untracked files
git clean -fd
```

### Pre-commit Hook
```bash
# Run pre-commit checks manually
mix precommit

# Install git hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
mix precommit
EOF
chmod +x .git/hooks/pre-commit
```

---

## 🔍 Useful Queries

### Find Files
```bash
# Find Elixir files
find lib -name "*.ex"

# Find test files
find test -name "*_test.exs"

# Find files containing text
grep -r "TODO" lib --include="*.ex"

# Find large files
find . -type f -size +1M
```

### Code Statistics
```bash
# Count lines of code
find lib -name "*.ex" | xargs wc -l

# Count test files
find test -name "*_test.exs" | wc -l

# List modules
grep -r "^defmodule" lib --include="*.ex" | wc -l
```

---

## 💡 Pro Tips

### Aliases (add to your shell config)
```bash
# Add to ~/.zshrc or ~/.bashrc
alias mt="mix test"
alias mts="mix test --stale"
alias mtf="mix test --failed"
alias mc="mix compile"
alias mpc="mix precommit"
alias mps="mix phx.server"
alias fdep="fly deploy"
alias flog="fly logs"
alias fssh="fly ssh console"
```

### Quick Problem Solving
```bash
# App won't compile?
mix clean && mix deps.get && mix compile

# Tests failing randomly?
mix test --seed 0  # Use consistent seed

# Database issues?
mix ecto.reset

# Native NIF issues?
mix clean.native && mix compile.native

# Fly.io deployment stuck?
fly deploy --no-cache
```

---

## 📚 Documentation

### Generate Documentation
```bash
# Generate HTML docs
mix docs

# Open docs in browser
open doc/index.html
```

### View Documentation
```bash
# In IEx
h(ModuleName)
h(ModuleName.function_name)

# Online
open https://hexdocs.pm/phoenix/
open https://hexdocs.pm/ecto/
```

---

## 🎯 Common Workflows

### Full Development Cycle
```bash
# 1. Start fresh
mix clean && mix deps.get

# 2. Setup database
mix ecto.reset

# 3. Compile everything
mix compile && mix compile.native

# 4. Run tests
mix test

# 5. Fix warnings
mix precommit

# 6. Start server
mix phx.server
```

### Pre-Deployment Checklist
```bash
# 1. All tests pass
mix test

# 2. No warnings
mix compile --warnings-as-errors

# 3. Code quality
mix precommit

# 4. Dependencies updated
mix hex.outdated

# 5. Migrations ready
mix ash_postgres.generate_migrations --check

# 6. Secrets configured
fly secrets list

# 7. Deploy
fly deploy
```

---

**Remember:** Most commands can be run with `--help` flag for more options:
```bash
mix help phx.server
fly help deploy
mix help test
```

🚀 **Happy Coding!**