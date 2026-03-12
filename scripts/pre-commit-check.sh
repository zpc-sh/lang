#!/bin/bash

# Pre-commit check script for LANG Universal Text Intelligence Platform
# Prevents committing build artifacts, secrets, and other sensitive files

set -e

echo "🔍 Running pre-commit checks..."

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Track if we found any issues
ISSUES_FOUND=0

# Function to report issues
report_issue() {
    echo -e "${RED}❌ $1${NC}"
    ISSUES_FOUND=1
}

report_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

report_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Check for build artifacts in staged files
echo "Checking for build artifacts..."

# Get staged files
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")

if [ -z "$STAGED_FILES" ]; then
    echo "No staged files found."
    exit 0
fi

# Check for Rust build artifacts
if echo "$STAGED_FILES" | grep -q "target/"; then
    report_issue "Rust build artifacts found in staged files (target/ directories)"
fi

if echo "$STAGED_FILES" | grep -q "Cargo\.lock"; then
    report_warning "Cargo.lock files found - these are usually auto-generated"
fi

# Check for compiled libraries
if echo "$STAGED_FILES" | grep -E "\.(so|dll|dylib)$"; then
    report_issue "Compiled native libraries found (.so/.dll/.dylib files)"
fi

# Check for Mix build artifacts
if echo "$STAGED_FILES" | grep -q "_build/"; then
    report_issue "Mix build artifacts found (_build/ directory)"
fi

if echo "$STAGED_FILES" | grep -q "deps/"; then
    report_issue "Mix dependencies found (deps/ directory)"
fi

# Check for Node.js artifacts
if echo "$STAGED_FILES" | grep -q "node_modules/"; then
    report_issue "Node.js modules found (node_modules/ directory)"
fi

if echo "$STAGED_FILES" | grep -q "package-lock\.json"; then
    report_warning "package-lock.json found - verify if this should be committed"
fi

# Check for IDE and OS files
if echo "$STAGED_FILES" | grep -E "\.(DS_Store|swp|swo)$"; then
    report_issue "IDE/OS temporary files found (.DS_Store, .swp, .swo)"
fi

if echo "$STAGED_FILES" | grep -q "\.vscode/\|\.idea/"; then
    report_issue "IDE configuration directories found (.vscode/, .idea/)"
fi

# Check for log files
if echo "$STAGED_FILES" | grep -E "\.log$"; then
    report_issue "Log files found (.log files)"
fi

# Check for temporary files
if echo "$STAGED_FILES" | grep -E "\.(tmp|temp|bak|backup)$"; then
    report_issue "Temporary/backup files found"
fi

# Check for potential secrets and sensitive files
echo "Checking for potential secrets..."

# Check for files that might contain secrets
SECRET_PATTERNS=(
    "\.env$"
    "\.env\."
    "_key$"
    "_secret$"
    "api_key"
    "webhook"
    "stripe_"
    "password"
    "secret"
    "token"
)

for pattern in "${SECRET_PATTERNS[@]}"; do
    if echo "$STAGED_FILES" | grep -i "$pattern" | grep -v "\.example$" | grep -v "\.template$"; then
        report_warning "Potential secret file found matching pattern: $pattern"
    fi
done

# Check file contents for common secret patterns (only for small text files)
for file in $STAGED_FILES; do
    if [ -f "$file" ] && [ $(wc -c < "$file" 2>/dev/null || echo 0) -lt 100000 ]; then
        # Check for common secret patterns in content
        if file "$file" 2>/dev/null | grep -q "text"; then
            if grep -l -i -E "(api[_-]?key|secret[_-]?key|password|token)" "$file" 2>/dev/null; then
                # Additional check to avoid false positives on common words in code
                if grep -E "(sk_|pk_|rk_|[A-Za-z0-9]{32,})" "$file" 2>/dev/null; then
                    report_warning "File '$file' may contain API keys or tokens"
                fi
            fi
        fi
    fi
done

# Check for large files
echo "Checking for large files..."
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        size=$(wc -c < "$file" 2>/dev/null || echo 0)
        if [ "$size" -gt 10485760 ]; then  # 10MB
            report_warning "Large file found: $file ($(numfmt --to=iec $size))"
        fi
    fi
done

# Check for proper file permissions
echo "Checking file permissions..."
for file in $STAGED_FILES; do
    if [ -f "$file" ]; then
        # Check if script files are executable
        if echo "$file" | grep -E "\.(sh|py|rb|pl)$"; then
            if [ ! -x "$file" ]; then
                report_warning "Script file '$file' is not executable"
            fi
        fi
        
        # Check for files with overly permissive permissions
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null || echo "")
        if [ "$perms" = "777" ]; then
            report_warning "File '$file' has overly permissive permissions (777)"
        fi
    fi
done

# Run Elixir format check
echo "Checking Elixir code formatting..."
if command -v mix >/dev/null 2>&1; then
    elixir_files=$(echo "$STAGED_FILES" | grep "\.exs\?$" || echo "")
    if [ -n "$elixir_files" ]; then
        if ! mix format --check-formatted $elixir_files 2>/dev/null; then
            report_warning "Some Elixir files are not properly formatted. Run 'mix format' to fix."
        else
            report_success "Elixir code formatting looks good"
        fi
    fi
else
    report_warning "Mix not found - skipping Elixir format check"
fi

# Run credo if available
echo "Running Elixir static analysis..."
if command -v mix >/dev/null 2>&1 && mix help credo >/dev/null 2>&1; then
    elixir_files=$(echo "$STAGED_FILES" | grep "\.exs\?$" || echo "")
    if [ -n "$elixir_files" ]; then
        if ! mix credo --strict $elixir_files 2>/dev/null; then
            report_warning "Credo found some issues. Consider fixing before committing."
        else
            report_success "Credo static analysis passed"
        fi
    fi
else
    report_warning "Credo not available - skipping static analysis"
fi

# Summary
echo ""
echo "Pre-commit check summary:"
if [ $ISSUES_FOUND -eq 0 ]; then
    report_success "All checks passed!"
    echo ""
    echo "Safe to commit ✨"
    exit 0
else
    echo ""
    echo -e "${RED}Issues found that should be addressed before committing.${NC}"
    echo ""
    echo "To fix common issues:"
    echo "  • Run './scripts/clean.sh' to remove build artifacts"
    echo "  • Run 'mix format' to format Elixir code"
    echo "  • Review and remove any accidentally staged files"
    echo "  • Check .gitignore to prevent future issues"
    echo ""
    echo "To commit anyway (not recommended):"
    echo "  git commit --no-verify"
    echo ""
    exit 1
fi