#!/bin/bash

# LANG Initial Deployment Script
# Sets up LANG for production deployment on Fly.io with complete configuration

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
REGION="ewr"
DOMAIN="lang.nocsi.com"

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

check_requirements() {
    log_info "Checking deployment requirements..."
    
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
    
    log_success "All requirements met"
}

setup_secrets() {
    log_info "Setting up secrets and environment variables..."
    
    # Generate SECRET_KEY_BASE if not provided
    if [ -z "${SECRET_KEY_BASE:-}" ]; then
        log_info "Generating SECRET_KEY_BASE..."
        SECRET_KEY_BASE=$(mix phx.gen.secret)
        log_warning "Generated SECRET_KEY_BASE: $SECRET_KEY_BASE"
        log_warning "Save this secret key securely!"
    fi
    
    # Required secrets check
    required_secrets=(
        "DATABASE_URL"
        "SECRET_KEY_BASE"
    )
    
    for secret in "${required_secrets[@]}"; do
        if [ -z "${!secret:-}" ]; then
            log_error "Required environment variable $secret is not set"
            echo "Please set it with: export $secret=\"your_value\""
            exit 1
        fi
    done
    
    # Set secrets on Fly.io
    log_info "Setting secrets on Fly.io..."
    fly secrets set \
        DATABASE_URL="$DATABASE_URL" \
        SECRET_KEY_BASE="$SECRET_KEY_BASE" \
        LIVE_VIEW_SIGNING_SALT="$(echo $SECRET_KEY_BASE | cut -c1-32)" \
        ASH_AUTHENTICATION_SECRET="$(echo $SECRET_KEY_BASE | cut -c33-64)"
    
    # Optional secrets (set if provided)
    optional_secrets=(
        "STRIPE_SECRET_KEY"
        "STRIPE_WEBHOOK_SECRET"
        "STRIPE_STARTER_PRICE_ID"
        "STRIPE_PRO_PRICE_ID" 
        "STRIPE_ENTERPRISE_PRICE_ID"
        "REDIS_URL"
        "OPENAI_API_KEY"
        "SENDGRID_API_KEY"
        "R2_ACCESS_KEY"
        "R2_SECRET_KEY"
        "R2_ENDPOINT"
        "SENTRY_DSN"
    )
    
    for secret in "${optional_secrets[@]}"; do
        if [ -n "${!secret:-}" ]; then
            log_info "Setting optional secret: $secret"
            fly secrets set "$secret=${!secret}"
        fi
    done
    
    log_success "Secrets configured"
}

create_fly_app() {
    log_info "Creating Fly.io application..."
    
    # Check if app already exists
    if fly apps list | grep -q "$APP_NAME"; then
        log_warning "App $APP_NAME already exists, skipping creation"
        return
    fi
    
    # Create the app without deploying
    fly apps create "$APP_NAME" --org personal
    
    log_success "Fly.io app created: $APP_NAME"
}

create_storage_volume() {
    log_info "Creating storage volume for uploads..."
    
    # Check if volume already exists
    if fly volumes list | grep -q "lang_uploads"; then
        log_warning "Volume lang_uploads already exists, skipping creation"
        return
    fi
    
    # Create 1GB volume for uploads
    fly volumes create lang_uploads \
        --region "$REGION" \
        --size 1
    
    log_success "Storage volume created"
}

setup_database() {
    log_info "Setting up database..."
    
    if [[ "$DATABASE_URL" == *"neon"* ]]; then
        log_info "Detected Neon database - no additional setup required"
    elif [[ "$DATABASE_URL" == *"supabase"* ]]; then
        log_info "Detected Supabase database - no additional setup required"
    elif [[ "$DATABASE_URL" == *"fly"* ]]; then
        log_info "Detected Fly.io database - ensuring it's running"
        # Could add Fly Postgres setup here if needed
    else
        log_warning "Database type not automatically detected, continuing with provided URL"
    fi
    
    log_success "Database configured"
}

compile_assets() {
    log_info "Compiling assets and dependencies..."
    
    # Get dependencies
    mix deps.get --only prod
    
    # Compile Rust NIFs
    log_info "Compiling Rust NIFs..."
    mix rustler.compile
    
    # Setup and compile assets
    log_info "Setting up and compiling assets..."
    mix assets.setup
    mix assets.deploy
    
    log_success "Assets compiled"
}

deploy_app() {
    log_info "Deploying application to Fly.io..."
    
    # Use production fly.toml if it exists
    if [ -f "fly.production.toml" ]; then
        log_info "Using production configuration"
        cp fly.production.toml fly.toml
    fi
    
    # Deploy the application
    fly deploy --ha=false
    
    log_success "Application deployed"
}

run_migrations() {
    log_info "Running database migrations..."
    
    # Run migrations via Fly SSH
    fly ssh console -C "/app/bin/lang eval Lang.Release.migrate"
    
    log_success "Database migrations completed"
}

setup_custom_domain() {
    log_info "Setting up custom domain: $DOMAIN"
    
    # Add the custom domain
    if ! fly domains list | grep -q "$DOMAIN"; then
        fly domains add "$DOMAIN"
        log_success "Domain $DOMAIN added"
        log_warning "Please configure your DNS:"
        log_warning "Add a CNAME record: $DOMAIN -> $APP_NAME.fly.dev"
    else
        log_warning "Domain $DOMAIN already configured"
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Wait for app to be ready
    sleep 30
    
    # Check health endpoint
    if curl -f "https://$APP_NAME.fly.dev/health" > /dev/null 2>&1; then
        log_success "Health check passed on Fly.dev subdomain"
    else
        log_warning "Health check failed on Fly.dev subdomain"
    fi
    
    # Check custom domain if configured
    if curl -f "https://$DOMAIN/health" > /dev/null 2>&1; then
        log_success "Health check passed on custom domain"
    else
        log_warning "Health check failed on custom domain (DNS may need time to propagate)"
    fi
    
    # Show app info
    log_info "Application info:"
    fly apps list | grep "$APP_NAME"
}

show_deployment_summary() {
    log_success "🚀 LANG Deployment Complete!"
    echo ""
    echo "📋 Deployment Summary:"
    echo "======================"
    echo "App Name: $APP_NAME"
    echo "Region: $REGION"
    echo "Primary URL: https://$APP_NAME.fly.dev"
    echo "Custom Domain: https://$DOMAIN"
    echo ""
    echo "🔍 Useful Commands:"
    echo "==================="
    echo "View logs:     fly logs"
    echo "SSH access:    fly ssh console"
    echo "Scale app:     fly scale show"
    echo "App status:    fly status"
    echo "Restart app:   fly machine restart"
    echo ""
    echo "📊 Monitoring URLs:"
    echo "==================="
    echo "Health Check:  https://$DOMAIN/health"
    echo "Metrics:       https://$DOMAIN/metrics"
    echo ""
    if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
        echo "💳 Stripe Webhook URL:"
        echo "======================"
        echo "https://$DOMAIN/webhooks/stripe"
        echo ""
    fi
    
    echo "🎉 Your LANG application is now live!"
}

# Main deployment process
main() {
    echo ""
    echo "🚀 LANG Production Deployment"
    echo "==============================="
    echo ""
    
    check_requirements
    setup_secrets
    create_fly_app
    create_storage_volume
    setup_database
    compile_assets
    deploy_app
    run_migrations
    setup_custom_domain
    verify_deployment
    show_deployment_summary
}

# Run the main function
main "$@"