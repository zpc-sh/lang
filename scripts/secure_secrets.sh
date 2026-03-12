#!/bin/bash
# LANG Secrets Security Setup Script
# This script helps you secure your application secrets

set -e

echo "🔒 LANG Secrets Security Setup"
echo "=============================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env exists
if [ -f .env ]; then
    echo -e "${YELLOW}⚠️  Warning: .env file exists${NC}"
    
    # Check for live keys
    if grep -q "sk_live_" .env; then
        echo -e "${RED}🚨 CRITICAL: Live Stripe keys detected in .env!${NC}"
        echo "This is a security risk. We'll help you secure them."
        echo ""
    fi
fi

# Function to generate secure random strings
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-$1
}

# 1. Create secure environment files
echo "1️⃣ Setting up environment files..."

# Create .env.local for development (git-ignored)
if [ ! -f .env.local ]; then
    echo "Creating .env.local for local development..."
    cp .env.example .env.local
    echo -e "${GREEN}✓ Created .env.local${NC}"
else
    echo -e "${YELLOW}⚠️  .env.local already exists${NC}"
fi

# Create .env.test for testing (git-ignored)
if [ ! -f .env.test ]; then
    echo "Creating .env.test for testing..."
    cp .env.example .env.test
    # Add test-specific overrides
    echo "" >> .env.test
    echo "# Test Environment Overrides" >> .env.test
    echo "DATABASE_URL=postgres://postgres:postgres@localhost:5432/lang_test" >> .env.test
    echo "STRIPE_SECRET_KEY=sk_test_your_test_key_here" >> .env.test
    echo -e "${GREEN}✓ Created .env.test${NC}"
fi

# 2. Update .gitignore
echo ""
echo "2️⃣ Updating .gitignore..."

# Check if secrets are properly ignored
if ! grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo ".env" >> .gitignore
    echo -e "${GREEN}✓ Added .env to .gitignore${NC}"
fi

if ! grep -q "^\.env\.local$" .gitignore 2>/dev/null; then
    echo ".env.local" >> .gitignore
    echo -e "${GREEN}✓ Added .env.local to .gitignore${NC}"
fi

if ! grep -q "^\.env\.\*$" .gitignore 2>/dev/null; then
    echo ".env.*" >> .gitignore
    echo "!.env.example" >> .gitignore
    echo -e "${GREEN}✓ Added .env.* pattern to .gitignore${NC}"
fi

# 3. Create secrets directory
echo ""
echo "3️⃣ Setting up secrets directory..."

mkdir -p .secrets
chmod 700 .secrets

if ! grep -q "^\.secrets/$" .gitignore 2>/dev/null; then
    echo ".secrets/" >> .gitignore
    echo -e "${GREEN}✓ Created .secrets/ directory (git-ignored)${NC}"
fi

# 4. Check for exposed secrets in git history
echo ""
echo "4️⃣ Checking git history for exposed secrets..."

# Check if git is initialized
if [ -d .git ]; then
    # Look for common secret patterns
    EXPOSED_SECRETS=$(git log -p | grep -E "(sk_live_|pk_live_|sk_test_|pk_test_|whsec_|SECRET_KEY|API_KEY|PASSWORD)" | wc -l)
    
    if [ $EXPOSED_SECRETS -gt 0 ]; then
        echo -e "${RED}⚠️  Found $EXPOSED_SECRETS potential secrets in git history!${NC}"
        echo "   You should consider cleaning your git history."
        echo "   See: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository"
    else
        echo -e "${GREEN}✓ No obvious secrets found in git history${NC}"
    fi
fi

# 5. Create secure key storage script
echo ""
echo "5️⃣ Creating secure key management tools..."

cat > .secrets/encrypt_secret.sh << 'EOF'
#!/bin/bash
# Encrypt a secret using a master key

if [ $# -ne 2 ]; then
    echo "Usage: $0 <secret_name> <secret_value>"
    exit 1
fi

SECRET_NAME=$1
SECRET_VALUE=$2
MASTER_KEY=${MASTER_KEY:-$(cat ~/.lang_master_key 2>/dev/null)}

if [ -z "$MASTER_KEY" ]; then
    echo "Error: MASTER_KEY not set and ~/.lang_master_key not found"
    echo "Generate one with: openssl rand -base64 32 > ~/.lang_master_key"
    exit 1
fi

# Encrypt the secret
echo "$SECRET_VALUE" | openssl enc -aes-256-cbc -a -salt -pass pass:"$MASTER_KEY" > ".secrets/${SECRET_NAME}.enc"
chmod 600 ".secrets/${SECRET_NAME}.enc"

echo "✓ Encrypted secret saved to .secrets/${SECRET_NAME}.enc"
EOF

chmod +x .secrets/encrypt_secret.sh

cat > .secrets/decrypt_secret.sh << 'EOF'
#!/bin/bash
# Decrypt a secret using a master key

if [ $# -ne 1 ]; then
    echo "Usage: $0 <secret_name>"
    exit 1
fi

SECRET_NAME=$1
MASTER_KEY=${MASTER_KEY:-$(cat ~/.lang_master_key 2>/dev/null)}

if [ -z "$MASTER_KEY" ]; then
    echo "Error: MASTER_KEY not set and ~/.lang_master_key not found"
    exit 1
fi

if [ ! -f ".secrets/${SECRET_NAME}.enc" ]; then
    echo "Error: .secrets/${SECRET_NAME}.enc not found"
    exit 1
fi

# Decrypt the secret
openssl enc -aes-256-cbc -d -a -pass pass:"$MASTER_KEY" < ".secrets/${SECRET_NAME}.enc"
EOF

chmod +x .secrets/decrypt_secret.sh

echo -e "${GREEN}✓ Created encryption/decryption scripts${NC}"

# 6. Create development secrets loader
cat > load_secrets.sh << 'EOF'
#!/bin/bash
# Load development secrets safely

ENV_FILE=${1:-.env.local}

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found"
    echo "Usage: source load_secrets.sh [.env.local|.env.test]"
    return 1 2>/dev/null || exit 1
fi

# Check if being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed"
    echo "Usage: source load_secrets.sh"
    exit 1
fi

# Load the environment file
set -a
source "$ENV_FILE"
set +a

echo "✓ Loaded secrets from $ENV_FILE"
echo "  Note: These are only set in your current shell session"
EOF

chmod +x load_secrets.sh

# 7. Create production secrets template
echo ""
echo "6️⃣ Creating production secrets management..."

cat > deploy/secrets.production.yml.example << 'EOF'
# Production Secrets Template for Fly.io
# Copy to secrets.production.yml and fill with real values
# NEVER commit secrets.production.yml to git!

# Required Secrets
SECRET_KEY_BASE: "generate-with-mix-phx.gen.secret"
LIVE_VIEW_SIGNING_SALT: "generate-with-mix-phx.gen.secret-32"
ASH_AUTHENTICATION_SECRET: "generate-with-mix-phx.gen.secret-64"
ENCRYPTION_KEY: "generate-with-crypto.strong_rand_bytes"

# Database
DATABASE_URL: "postgres://user:pass@host:5432/lang_prod"

# Stripe (Production Keys)
STRIPE_SECRET_KEY: "sk_live_xxx"
STRIPE_PUBLISHABLE_KEY: "pk_live_xxx"
STRIPE_WEBHOOK_SECRET: "whsec_xxx"
STRIPE_PRO_PRICE_ID: "price_xxx"
STRIPE_BUSINESS_PRICE_ID: "price_xxx"

# External Services
OPENAI_API_KEY: "sk-xxx"
SENDGRID_API_KEY: "SG.xxx"
EOF

# Add to .gitignore
if ! grep -q "secrets\.production\.yml" .gitignore 2>/dev/null; then
    echo "deploy/secrets.production.yml" >> .gitignore
    echo -e "${GREEN}✓ Created production secrets template${NC}"
fi

# 8. Create secrets validation script
cat > scripts/validate_secrets.exs << 'EOF'
# Validate that all required secrets are present
# Run with: mix run scripts/validate_secrets.exs

defmodule SecretsValidator do
  @required_secrets [
    # Core secrets
    "SECRET_KEY_BASE",
    "LIVE_VIEW_SIGNING_SALT",
    "ASH_AUTHENTICATION_SECRET",
    "ENCRYPTION_KEY",
    
    # Database
    "DATABASE_URL",
    
    # Stripe (for production)
    "STRIPE_SECRET_KEY",
    "STRIPE_WEBHOOK_SECRET"
  ]
  
  @optional_secrets [
    "STRIPE_PUBLISHABLE_KEY",
    "STRIPE_PRO_PRICE_ID",
    "STRIPE_BUSINESS_PRICE_ID",
    "OPENAI_API_KEY",
    "SENDGRID_API_KEY",
    "REDIS_URL"
  ]
  
  def validate_all do
    IO.puts("🔍 Validating secrets configuration...")
    IO.puts("")
    
    missing_required = check_required_secrets()
    missing_optional = check_optional_secrets()
    check_secret_quality()
    
    if missing_required == [] do
      IO.puts("\n✅ All required secrets are configured!")
    else
      IO.puts("\n❌ Missing required secrets:")
      Enum.each(missing_required, &IO.puts("   - #{&1}"))
      System.halt(1)
    end
    
    if missing_optional != [] do
      IO.puts("\n⚠️  Missing optional secrets:")
      Enum.each(missing_optional, &IO.puts("   - #{&1}"))
    end
  end
  
  defp check_required_secrets do
    Enum.filter(@required_secrets, fn key ->
      System.get_env(key) == nil
    end)
  end
  
  defp check_optional_secrets do
    Enum.filter(@optional_secrets, fn key ->
      System.get_env(key) == nil
    end)
  end
  
  defp check_secret_quality do
    IO.puts("🔐 Checking secret quality...")
    
    # Check SECRET_KEY_BASE length
    if secret = System.get_env("SECRET_KEY_BASE") do
      if byte_size(secret) < 64 do
        IO.puts("   ⚠️  SECRET_KEY_BASE should be at least 64 characters")
      else
        IO.puts("   ✓ SECRET_KEY_BASE length OK")
      end
    end
    
    # Check for test keys in production
    if Mix.env() == :prod do
      stripe_key = System.get_env("STRIPE_SECRET_KEY")
      if stripe_key && String.starts_with?(stripe_key, "sk_test_") do
        IO.puts("   ⚠️  Using TEST Stripe keys in production!")
      end
    end
    
    # Check for default/example values
    Enum.each(@required_secrets, fn key ->
      if value = System.get_env(key) do
        if String.contains?(value, "your-") || String.contains?(value, "xxx") do
          IO.puts("   ⚠️  #{key} appears to contain an example value")
        end
      end
    end)
  end
end

SecretsValidator.validate_all()
EOF

echo -e "${GREEN}✓ Created secrets validation script${NC}"

# 9. Create fly.io secrets management script
cat > scripts/deploy_secrets.sh << 'EOF'
#!/bin/bash
# Deploy secrets to Fly.io

if [ ! -f deploy/secrets.production.yml ]; then
    echo "Error: deploy/secrets.production.yml not found"
    echo "Copy deploy/secrets.production.yml.example and fill in your values"
    exit 1
fi

echo "🚀 Deploying secrets to Fly.io..."

# Parse YAML and set secrets
while IFS=': ' read -r key value; do
    if [[ ! -z "$key" ]] && [[ ! "$key" =~ ^# ]] && [[ ! -z "$value" ]]; then
        # Remove quotes from value
        value="${value%\"}"
        value="${value#\"}"
        echo "Setting $key..."
        fly secrets set "$key=$value" --stage
    fi
done < deploy/secrets.production.yml

echo ""
echo "✓ Secrets staged. Deploy with: fly secrets deploy"
EOF

chmod +x scripts/deploy_secrets.sh

# 10. Generate master key if needed
echo ""
echo "7️⃣ Setting up master encryption key..."

if [ ! -f ~/.lang_master_key ]; then
    echo "Generating master encryption key..."
    openssl rand -base64 32 > ~/.lang_master_key
    chmod 600 ~/.lang_master_key
    echo -e "${GREEN}✓ Generated master key at ~/.lang_master_key${NC}"
    echo "  ⚠️  Back this up securely! You'll need it to decrypt secrets."
else
    echo -e "${YELLOW}⚠️  Master key already exists at ~/.lang_master_key${NC}"
fi

# 11. Create comprehensive .env.example
echo ""
echo "8️⃣ Updating .env.example with all required variables..."

cat > .env.example << 'EOF'
# LANG Universal Text Intelligence Platform
# Environment Configuration Template
#
# Copy this file to .env.local for development
# Never commit .env or .env.local to version control!
#
# For production, use fly secrets or your deployment platform's secret management

# ===== REQUIRED SECRETS =====

# Phoenix Secret Key Base (generate with: mix phx.gen.secret)
SECRET_KEY_BASE=your-secret-key-base-here-min-64-chars

# LiveView Signing Salt (generate with: mix phx.gen.secret 32)
LIVE_VIEW_SIGNING_SALT=your-32-char-salt-here

# AshAuthentication Secret (generate with: mix phx.gen.secret 64)
ASH_AUTHENTICATION_SECRET=your-64-char-secret-here

# Encryption Key (generate in iex: :crypto.strong_rand_bytes(32) |> Base.encode64())
ENCRYPTION_KEY=your-base64-encoded-32-byte-key-here

# ===== DATABASE =====

# Full Database URL (preferred)
DATABASE_URL=postgres://postgres:postgres@localhost:5432/lang_dev

# ===== STRIPE BILLING =====
# Get these from https://dashboard.stripe.com/apikeys
# Use test keys for development!

# Secret key (starts with sk_test_ for development)
STRIPE_SECRET_KEY=sk_test_your_test_key_here

# Publishable key (starts with pk_test_ for development)  
STRIPE_PUBLISHABLE_KEY=pk_test_your_test_key_here

# Webhook signing secret (get from Stripe dashboard > Webhooks)
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret_here

# Price IDs (create with scripts/setup_stripe.sh)
STRIPE_PRO_PRICE_ID=price_xxx
STRIPE_BUSINESS_PRICE_ID=price_xxx

# URLs for Stripe checkout
STRIPE_SUCCESS_URL=http://localhost:4000/dashboard?success=true
STRIPE_CANCEL_URL=http://localhost:4000/dashboard?canceled=true

# ===== APPLICATION CONFIG =====

# Application host and port
APP_HOST=localhost
PORT=4000
PHX_HOST=localhost

# LSP Server Port
LSP_PORT=4001

# ===== OPTIONAL SERVICES =====

# Redis for caching (optional)
REDIS_URL=redis://localhost:6379/0

# AI Services (optional)
OPENAI_API_KEY=sk-your-openai-key
ANTHROPIC_API_KEY=sk-ant-your-anthropic-key

# Email Service (optional)
SENDGRID_API_KEY=SG.your-sendgrid-key

# ===== SECURITY =====

# Rate limiting
RATE_LIMITING_ENABLED=true
RATE_LIMIT_RPM=60

# CORS
CORS_ENABLED=true
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:4000

# ===== QUICK START =====
#
# 1. Copy this file: cp .env.example .env.local
# 2. Generate secrets:
#    mix phx.gen.secret              # For SECRET_KEY_BASE
#    mix phx.gen.secret 32           # For LIVE_VIEW_SIGNING_SALT  
#    mix phx.gen.secret 64           # For ASH_AUTHENTICATION_SECRET
# 3. Start services:
#    docker-compose up -d            # Starts Postgres & Redis
# 4. Load secrets:
#    source load_secrets.sh          # Loads .env.local
# 5. Setup:
#    mix setup                       # Install deps & create DB
# 6. Start:
#    mix phx.server                  # Start the application
EOF

echo -e "${GREEN}✓ Updated .env.example${NC}"

# 12. Final security check
echo ""
echo "9️⃣ Running final security check..."

# Remove .env if it contains live keys
if [ -f .env ] && grep -q "sk_live_" .env; then
    echo -e "${RED}🚨 Moving .env with live keys to .secrets/env.backup${NC}"
    mv .env .secrets/env.backup
    chmod 600 .secrets/env.backup
    echo "   Your live keys have been backed up to .secrets/env.backup"
    echo "   Use .env.local for development instead"
fi

# Create safe .env.local if needed
if [ ! -f .env.local ] && [ -f .secrets/env.backup ]; then
    echo "Creating safe .env.local for development..."
    cp .env.example .env.local
    # Copy non-sensitive values from backup
    grep -E "^(APP_HOST|PORT|PHX_HOST|LSP_PORT|LOG_LEVEL)" .secrets/env.backup >> .env.local || true
    echo -e "${GREEN}✓ Created .env.local with safe defaults${NC}"
fi

# Summary
echo ""
echo "✅ Security Setup Complete!"
echo "=========================="
echo ""
echo "📋 Next Steps:"
echo "1. Edit .env.local and add your DEVELOPMENT keys (sk_test_...)"
echo "2. Run: source load_secrets.sh"
echo "3. Run: mix run scripts/validate_secrets.exs"
echo "4. For production deployment:"
echo "   - Copy deploy/secrets.production.yml.example"
echo "   - Fill in production values"
echo "   - Run: ./scripts/deploy_secrets.sh"
echo ""
echo "🔐 Security Best Practices:"
echo "• Never commit .env files to git"
echo "• Use test keys for development (sk_test_...)"
echo "• Use fly secrets or equivalent for production"
echo "• Rotate keys regularly"
echo "• Back up your master key (~/.lang_master_key) securely"
echo ""
echo "⚠️  Important: If you previously committed secrets to git,"
echo "   consider rotating all keys and cleaning git history!"
EOF