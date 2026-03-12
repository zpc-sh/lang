#!/bin/bash

# LANG Regular Deployment Script
# For updating an already deployed LANG application

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="lang-floral-firefly-7929"
HEALTH_CHECK_URL="https://lang.nocsi.com/health"
MAX_HEALTH_CHECK_ATTEMPTS=10
HEALTH_CHECK_WAIT=10

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    log_info "Checking deployment prerequisites..."
    
    # Check if fly CLI is installed
    if ! command -v fly &> /dev/null; then
        log_error "Fly CLI is not installed. Please install it from https://fly.io/docs/getting-started/installing-flyctl/"
        exit 1
    fi
    
    # Check if logged into Fly.io
    if ! fly auth whoami &> /dev/null; then
        log_error "Not logged into Fly.io. Please run 'fly auth login'"
        exit 1
    fi
    
    # Check if we're in the right directory
    if [ ! -f "mix.exs" ]; then
        log_error "mix.exs not found. Please run this script from the LANG project root directory."
        exit 1
    fi
    
    # Check if Mix is available
    if ! command -v mix &> /dev/null; then
        log_error "Elixir/Mix is not installed. Please install Elixir."
        exit 1
    fi
    
    # Check if Rust is available for NIFs
    if ! command -v cargo &> /dev/null; then
        log_error "Rust/Cargo is not installed. Rust is required for NIFs."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

pre_deployment_checks() {
    log_info "Running pre-deployment checks..."
    
    # Check if there are any uncommitted changes
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        log_warning "There are uncommitted changes in the repository"
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Run tests
    log_info "Running tests..."
    if ! mix test; then
        log_error "Tests failed. Please fix failing tests before deploying."
        exit 1
    fi
    
    log_success "Pre-deployment checks passed"
}

update_dependencies() {
    log_info "Updating dependencies..."
    
    # Clean and get dependencies
    mix deps.clean --unused
    mix deps.get --only prod
    
    log_success "Dependencies updated"
}

compile_native_extensions() {
    log_info "Compiling Rust NIFs..."
    
    # Clean previous builds
    mix rustler.clean
    
    # Ensure Rust toolchain is available
    if ! command -v cargo &> /dev/null; then
        log_error "Rust/Cargo not found. Please install Rust toolchain."
        exit 1
    fi
    
    # Verify all NIF directories exist
    nif_dirs=("native/lang_parser" "native/lang_perf" "native/fs_watcher" "native/tree_parser" "native/fs_scanner")
    for dir in "${nif_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_warning "NIF directory $dir not found, skipping"
        else
            log_info "Found NIF: $dir"
        fi
    done
    
    # Compile all Rust NIFs with proper error handling
    if mix rustler.compile; then
        log_success "All Rust NIFs compiled successfully"
        
        # Verify NIF compilation by checking for .so files
        nif_count=$(find . -name "*.so" -path "./native/*" | wc -l)
        log_info "Compiled $nif_count NIF libraries"
    else
        log_error "Failed to compile Rust NIFs"
        log_info "Troubleshooting steps:"
        log_info "1. Check Rust version: cargo --version"
        log_info "2. Update Rust: rustup update"
        log_info "3. Check dependencies: cargo check"
        exit 1
    fi
}

build_assets() {
    log_info "Building assets..."
    
    # Setup assets (install dependencies if needed)
    mix assets.setup
    
    # Deploy assets (compile and minify)
    mix assets.deploy
    
    log_success "Assets built"
}

backup_current_version() {
    log_info "Creating backup of current version..."
    
    # Get current version info before deployment
    CURRENT_VERSION=$(fly status --json | jq -r '.Version // "unknown"')
    log_info "Current version: $CURRENT_VERSION"
    
    # Store version info for potential rollback
    echo "$CURRENT_VERSION" > .last_deployed_version
    
    log_success "Backup information stored"
}

deploy_application() {
    log_info "Deploying application..."
    
    # Use production fly.toml if it exists
    if [ -f "fly.production.toml" ]; then
        log_info "Using production configuration"
        cp fly.production.toml fly.toml
    fi
    
    # Pre-deployment verification
    log_info "Verifying build artifacts..."
    
    # Check for compiled NIFs
    nif_count=$(find . -name "*.so" -path "./native/*" | wc -l)
    if [ "$nif_count" -gt 0 ]; then
        log_success "Found $nif_count compiled NIF libraries"
    else
        log_warning "No compiled NIFs found - deployment may fail"
    fi
    
    # Check for compiled assets
    if [ -d "priv/static" ]; then
        log_success "Compiled assets found"
    else
        log_warning "No compiled assets found"
    fi
    
    # Deploy with zero-downtime strategy
    log_info "Starting deployment to Fly.io..."
    if fly deploy --ha=false --strategy immediate; then
        log_success "Application deployed successfully"
        
        # Wait for deployment to be ready
        log_info "Waiting for deployment to be ready..."
        sleep 15
    else
        log_error "Deployment failed"
        log_info "Check logs with: fly logs --lines 50"
        exit 1
    fi
}

run_database_migrations() {
    log_info "Running database migrations..."
    
    # Check if there are pending migrations
    MIGRATION_STATUS=$(fly ssh console -C "/app/bin/lang eval 'Ecto.Migrator.migrations(Lang.Repo) |> Enum.filter(fn {_, _, status} -> status == :down end) |> length()'" 2>/dev/null || echo "unknown")
    
    if [ "$MIGRATION_STATUS" = "0" ]; then
        log_info "No pending migrations"
    elif [ "$MIGRATION_STATUS" = "unknown" ]; then
        log_warning "Could not check migration status, running migrations anyway"
        fly ssh console -C "/app/bin/lang eval Lang.Release.migrate"
    else
        log_info "Found $MIGRATION_STATUS pending migrations"
        fly ssh console -C "/app/bin/lang eval Lang.Release.migrate"
    fi
    
    log_success "Database migrations completed"
}

verify_health_check() {
    log_info "Verifying application health..."
    
    local attempt=1
    local max_attempts=$MAX_HEALTH_CHECK_ATTEMPTS
    local wait_time=$HEALTH_CHECK_WAIT
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Health check attempt $attempt/$max_attempts..."
        
        if curl -f --max-time 30 "$HEALTH_CHECK_URL" > /dev/null 2>&1; then
            log_success "Health check passed!"
            
            # Get and display health status
            HEALTH_STATUS=$(curl -s "$HEALTH_CHECK_URL" | jq -r '.status // "unknown"')
            VERSION=$(curl -s "$HEALTH_CHECK_URL" | jq -r '.version // "unknown"')
            
            log_info "Application status: $HEALTH_STATUS"
            log_info "Application version: $VERSION"
            
            return 0
        else
            log_warning "Health check failed (attempt $attempt/$max_attempts)"
            
            if [ $attempt -lt $max_attempts ]; then
                log_info "Waiting ${wait_time}s before next attempt..."
                sleep $wait_time
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Health check failed after $max_attempts attempts"
    return 1
}

run_post_deployment_tasks() {
    log_info "Running post-deployment tasks..."
    
    # Warm up the application
    log_info "Warming up application..."
    curl -s "$HEALTH_CHECK_URL" > /dev/null || true
    
    # Clear any cached data if needed
    log_info "Clearing application caches..."
    fly ssh console -C "/app/bin/lang eval 'Cachex.clear(:default_cache)'" > /dev/null 2>&1 || true
    
    # Send deployment notification if webhook is configured
    if [ -n "${DEPLOYMENT_WEBHOOK_URL:-}" ]; then
        log_info "Sending deployment notification..."
        curl -X POST "$DEPLOYMENT_WEBHOOK_URL" \
             -H "Content-Type: application/json" \
             -d "{\"status\": \"deployed\", \"app\": \"$APP_NAME\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
             > /dev/null 2>&1 || log_warning "Failed to send deployment notification"
    fi
    
    log_success "Post-deployment tasks completed"
}

show_deployment_info() {
    log_success "🎉 Deployment completed successfully!"
    echo ""
    echo "📊 Deployment Information:"
    echo "=========================="
    
    # Get app status
    APP_STATUS=$(fly status --json 2>/dev/null || echo "{}")
    
    # Extract information
    VERSION=$(echo "$APP_STATUS" | jq -r '.Version // "unknown"')
    PLATFORM_VERSION=$(echo "$APP_STATUS" | jq -r '.PlatformVersion // "unknown"')
    
    echo "App Name: $APP_NAME"
    echo "Version: $VERSION"
    echo "Platform: $PLATFORM_VERSION"
    echo "Health URL: $HEALTH_CHECK_URL"
    echo ""
    
    echo "🔍 Useful Commands:"
    echo "==================="
    echo "View logs:        fly logs"
    echo "App status:       fly status"
    echo "SSH access:       fly ssh console"
    echo "Scale machines:   fly scale show"
    echo "Machine restart:  fly machine restart"
    echo ""
    
    echo "📈 Monitoring:"
    echo "=============="
    echo "Health check:     curl $HEALTH_CHECK_URL"
    echo "App metrics:      https://lang.nocsi.com/metrics"
    echo "Fly dashboard:    https://fly.io/apps/$APP_NAME"
    echo ""
    
    # Show recent logs
    echo "📋 Recent logs (last 10 lines):"
    echo "================================"
    fly logs --lines 10
}

rollback_deployment() {
    log_error "Deployment verification failed!"
    
    if [ -f ".last_deployed_version" ]; then
        LAST_VERSION=$(cat .last_deployed_version)
        log_warning "Consider rolling back to version: $LAST_VERSION"
        echo ""
        echo "To rollback manually:"
        echo "fly apps releases --json | jq -r '.[1].Version' # Get previous version"
        echo "fly deploy --image registry.fly.io/$APP_NAME:<version>"
    fi
    
    echo ""
    echo "Troubleshooting commands:"
    echo "fly logs --lines 100"
    echo "fly ssh console"
    echo "fly status"
    
    exit 1
}

# Main deployment process
main() {
    echo ""
    echo "🚀 LANG Update Deployment"
    echo "========================="
    echo ""
    
    check_prerequisites
    pre_deployment_checks
    update_dependencies
    compile_native_extensions
    build_assets
    backup_current_version
    deploy_application
    run_database_migrations
    
    if verify_health_check; then
        run_post_deployment_tasks
        show_deployment_info
    else
        rollback_deployment
    fi
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "quick")
        log_info "Running quick deployment (skipping tests)..."
        check_prerequisites
        compile_native_extensions
        build_assets
        deploy_application
        verify_health_check || rollback_deployment
        ;;
    "rollback")
        if [ -f ".last_deployed_version" ]; then
            LAST_VERSION=$(cat .last_deployed_version)
            log_info "Rolling back to version: $LAST_VERSION"
            fly deploy --image "registry.fly.io/$APP_NAME:$LAST_VERSION"
        else
            log_error "No previous version information found"
            exit 1
        fi
        ;;
    "help")
        echo "LANG Deployment Script"
        echo "====================="
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  deploy    - Full deployment with tests and verification (default)"
        echo "  quick     - Quick deployment without tests"
        echo "  rollback  - Rollback to previous version"
        echo "  help      - Show this help message"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac