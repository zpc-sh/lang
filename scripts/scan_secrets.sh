#!/bin/bash
# Comprehensive secret scanning script for LANG

set -e

echo "🔍 LANG Secret Scanner"
echo "===================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
ISSUES=0
WARNINGS=0

# Function to check files
check_files() {
    local pattern=$1
    local description=$2
    local severity=$3
    
    echo -e "${BLUE}Checking for ${description}...${NC}"
    
    # Check in current files
    CURRENT_FILES=$(git ls-files | xargs grep -l "$pattern" 2>/dev/null || true)
    if [ ! -z "$CURRENT_FILES" ]; then
        echo -e "${RED}❌ Found in current files:${NC}"
        echo "$CURRENT_FILES" | while read file; do
            echo "   - $file"
            if [ "$severity" = "critical" ]; then
                ((ISSUES++))
            else
                ((WARNINGS++))
            fi
        done
    fi
    
    # Check in git history
    HISTORY_COUNT=$(git log -p --all | grep -c "$pattern" 2>/dev/null || echo "0")
    if [ "$HISTORY_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Found $HISTORY_COUNT occurrences in git history${NC}"
        ((WARNINGS++))
    fi
}

echo "1️⃣ Checking for Stripe keys..."
echo "==============================="

# Live Stripe keys (CRITICAL)
check_files "sk_live_[A-Za-z0-9]{24,}" "Live Stripe Secret Keys" "critical"
check_files "pk_live_[A-Za-z0-9]{24,}" "Live Stripe Publishable Keys" "warning"
check_files "whsec_[A-Za-z0-9]{24,}" "Stripe Webhook Secrets" "critical"

# Test Stripe keys (WARNING)
check_files "sk_test_[A-Za-z0-9]{24,}" "Test Stripe Secret Keys" "warning"
check_files "pk_test_[A-Za-z0-9]{24,}" "Test Stripe Publishable Keys" "info"

echo ""
echo "2️⃣ Checking for database credentials..."
echo "======================================="

# Database URLs with passwords
check_files "postgres://[^:]+:[^@]+@[^/]+" "PostgreSQL URLs with passwords" "critical"
check_files "mysql://[^:]+:[^@]+@[^/]+" "MySQL URLs with passwords" "critical"
check_files "mongodb://[^:]+:[^@]+@[^/]+" "MongoDB URLs with passwords" "critical"

echo ""
echo "3️⃣ Checking for API keys..."
echo "============================"

# Common API key patterns
check_files "api[_-]?key[\"'\s]*[:=][\"'\s]*[A-Za-z0-9_-]{20,}" "API Keys" "critical"
check_files "secret[_-]?key[\"'\s]*[:=][\"'\s]*[A-Za-z0-9_-]{20,}" "Secret Keys" "critical"
check_files "access[_-]?token[\"'\s]*[:=][\"'\s]*[A-Za-z0-9_-]{20,}" "Access Tokens" "critical"

# Specific service patterns
check_files "sk-[A-Za-z0-9]{48}" "OpenAI API Keys" "critical"
check_files "SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}" "SendGrid API Keys" "critical"
check_files "AKIA[0-9A-Z]{16}" "AWS Access Keys" "critical"

echo ""
echo "4️⃣ Checking for other secrets..."
echo "================================"

# Phoenix/Elixir specific
check_files "SECRET_KEY_BASE[\"'\s]*[:=][\"'\s]*[A-Za-z0-9+/]{64,}" "Phoenix Secret Key Base" "critical"
check_files "SIGNING_SALT[\"'\s]*[:=][\"'\s]*[A-Za-z0-9+/]{32,}" "Phoenix Signing Salt" "critical"

# Generic patterns
check_files "password[\"'\s]*[:=][\"'\s]*[^\"'\s]{8,}" "Passwords" "critical"
check_files "private[_-]?key[\"'\s]*[:=][\"'\s]*[A-Za-z0-9+/]{20,}" "Private Keys" "critical"

echo ""
echo "5️⃣ Checking committed files that shouldn't be..."
echo "================================================"

# Check for files that should never be committed
DANGEROUS_FILES=".env .env.local .env.production secrets.yml credentials.json"
for file in $DANGEROUS_FILES; do
    if [ -f "$file" ]; then
        echo -e "${RED}❌ CRITICAL: $file exists in repository!${NC}"
        ((ISSUES++))
    fi
    
    # Check history
    if git log --all --full-history -- "$file" | grep -q commit; then
        echo -e "${YELLOW}⚠️  WARNING: $file was previously committed${NC}"
        ((WARNINGS++))
    fi
done

echo ""
echo "6️⃣ Checking .gitignore effectiveness..."
echo "========================================"

# Test if .gitignore is working
touch .env.test.scanner
if git check-ignore .env.test.scanner > /dev/null 2>&1; then
    echo -e "${GREEN}✓ .gitignore is properly ignoring .env files${NC}"
else
    echo -e "${RED}❌ .gitignore is NOT properly configured!${NC}"
    ((ISSUES++))
fi
rm -f .env.test.scanner

echo ""
echo "7️⃣ Summary"
echo "=========="

if [ $ISSUES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ No secrets found! Your repository appears clean.${NC}"
else
    echo -e "${RED}Found $ISSUES critical issues and $WARNINGS warnings${NC}"
    echo ""
    echo "Recommended actions:"
    
    if [ $ISSUES -gt 0 ]; then
        echo "1. IMMEDIATELY rotate any exposed production keys"
        echo "2. Remove sensitive files from the repository"
        echo "3. Clean git history if secrets were committed"
    fi
    
    if [ $WARNINGS -gt 0 ]; then
        echo "- Review warnings and determine if action needed"
        echo "- Consider cleaning git history for test keys"
        echo "- Update documentation with security notes"
    fi
fi

echo ""
echo "🛠️  Useful commands:"
echo "==================="
echo ""
echo "# Remove a file from history (DESTRUCTIVE):"
echo "git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch PATH_TO_FILE' --prune-empty --tag-name-filter cat -- --all"
echo ""
echo "# Find commits that added secrets:"
echo "git log -p -S 'sk_live' --all"
echo ""
echo "# Check what .gitignore is ignoring:"
echo "git check-ignore -v .env"
echo ""

# Return exit code based on issues found
if [ $ISSUES -gt 0 ]; then
    exit 1
else
    exit 0
fi