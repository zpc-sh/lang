#!/bin/bash
# Quick script to migrate from exposed .env to secure setup

echo "🔄 LANG Secrets Migration Tool"
echo "=============================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check current situation
if [ -f .env ]; then
    echo -e "${YELLOW}Found existing .env file${NC}"
    
    # Check for live keys
    if grep -q "sk_live_" .env; then
        echo -e "${RED}⚠️  WARNING: Live Stripe keys detected!${NC}"
        echo ""
        echo "This script will help you secure them."
        read -p "Continue? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "Migration cancelled."
            exit 0
        fi
    fi
    
    # Backup current .env
    echo ""
    echo "1️⃣ Backing up current .env..."
    mkdir -p .secrets
    cp .env .secrets/env.backup.$(date +%Y%m%d_%H%M%S)
    chmod 600 .secrets/env.backup.*
    echo -e "${GREEN}✓ Backup created in .secrets/${NC}"
    
    # Create .env.local with test keys
    echo ""
    echo "2️⃣ Creating development environment..."
    
    cat > .env.local << 'EOF'
# LANG Development Environment
# Generated from migration script

# Copy non-sensitive values from original
EOF
    
    # Copy safe values
    grep -E "^(APP_HOST|PORT|PHX_HOST|LSP_PORT|LOG_LEVEL|CORS_|RATE_)" .env >> .env.local || true
    
    # Add test Stripe keys section
    cat >> .env.local << 'EOF'

# ===== STRIPE (TEST KEYS FOR DEVELOPMENT) =====
# Replace these with your Stripe TEST keys from https://dashboard.stripe.com/test/apikeys
STRIPE_SECRET_KEY=sk_test_REPLACE_ME
STRIPE_PUBLISHABLE_KEY=pk_test_REPLACE_ME
STRIPE_WEBHOOK_SECRET=whsec_REPLACE_ME

# These will be created by setup_stripe.sh
STRIPE_PRO_PRICE_ID=
STRIPE_BUSINESS_PRICE_ID=
EOF
    
    # Copy other non-sensitive values
    echo "" >> .env.local
    echo "# Other configuration" >> .env.local
    grep -v -E "(SECRET|KEY|PASSWORD|STRIPE_|sk_|pk_|whsec_)" .env >> .env.local || true
    
    echo -e "${GREEN}✓ Created .env.local for development${NC}"
    
    # Save production keys securely
    echo ""
    echo "3️⃣ Extracting production secrets..."
    
    # Create production template
    mkdir -p deploy
    cat > deploy/secrets.production.yml << EOF
# Production Secrets - KEEP SECURE!
# Generated from migration on $(date)

# Core Secrets (generate new ones for better security)
EOF
    
    # Extract current values
    grep -E "^(SECRET_KEY_BASE|LIVE_VIEW_SIGNING_SALT|ASH_AUTHENTICATION_SECRET|ENCRYPTION_KEY)" .env >> deploy/secrets.production.yml || true
    
    echo "" >> deploy/secrets.production.yml
    echo "# Database" >> deploy/secrets.production.yml
    grep "^DATABASE_URL" .env >> deploy/secrets.production.yml || true
    
    echo "" >> deploy/secrets.production.yml
    echo "# Stripe Production Keys" >> deploy/secrets.production.yml
    grep -E "^STRIPE_.*sk_live" .env >> deploy/secrets.production.yml || true
    grep -E "^STRIPE_.*pk_live" .env >> deploy/secrets.production.yml || true
    grep -E "^STRIPE_.*whsec" .env >> deploy/secrets.production.yml || true
    grep -E "^STRIPE_.*price_" .env >> deploy/secrets.production.yml || true
    
    chmod 600 deploy/secrets.production.yml
    echo -e "${GREEN}✓ Production secrets saved to deploy/secrets.production.yml${NC}"
    
    # Remove original .env
    echo ""
    echo "4️⃣ Removing exposed .env file..."
    rm .env
    echo -e "${GREEN}✓ Removed .env${NC}"
    
    # Update .gitignore
    echo ""
    echo "5️⃣ Updating .gitignore..."
    if ! grep -q "^\.env$" .gitignore; then
        echo ".env" >> .gitignore
    fi
    if ! grep -q "^deploy/secrets" .gitignore; then
        echo "deploy/secrets*.yml" >> .gitignore
        echo "!deploy/secrets*.example" >> .gitignore
    fi
    echo -e "${GREEN}✓ Updated .gitignore${NC}"
    
else
    echo "No .env file found. Creating fresh development setup..."
    cp .env.example .env.local
    echo -e "${GREEN}✓ Created .env.local from template${NC}"
fi

# Final instructions
echo ""
echo "✅ Migration Complete!"
echo "===================="
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Get your Stripe TEST keys from: https://dashboard.stripe.com/test/apikeys"
echo "   Edit .env.local and replace the STRIPE_*_KEY placeholders"
echo ""
echo "2. Load the development environment:"
echo "   source load_secrets.sh"
echo ""
echo "3. Set up Stripe products (using TEST keys):"
echo "   ./scripts/setup_stripe.sh"
echo ""
echo "4. For production deployment:"
echo "   - Review deploy/secrets.production.yml"
echo "   - Deploy using: ./scripts/deploy_secrets.sh"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT SECURITY STEPS:${NC}"
echo "1. Rotate ALL production keys that were in .env"
echo "2. Check git history: git log -p .env"
echo "3. If keys were committed, see: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository"
echo ""
echo "Your production keys are now in:"
echo "  - .secrets/env.backup.* (backup)"
echo "  - deploy/secrets.production.yml (for deployment)"
echo ""
echo "Keep these files secure and NEVER commit them!"