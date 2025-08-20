#!/bin/bash

# LANG Universal Text Intelligence Platform - Initialization Script
# This script sets up a complete LANG development environment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check Elixir
    if ! command_exists elixir; then
        log_error "Elixir is not installed. Please install Elixir 1.15+ and Erlang/OTP 24+"
        exit 1
    fi
    
    local elixir_version=$(elixir --version | grep "Elixir" | awk '{print $2}')
    log_success "Elixir $elixir_version detected"
    
    # Check PostgreSQL
    if ! command_exists psql; then
        log_error "PostgreSQL is not installed. Please install PostgreSQL 12+"
        exit 1
    fi
    
    # Check Redis
    if ! command_exists redis-cli; then
        log_warning "Redis not found. Some caching features may not work optimally"
    fi
    
    # Check Node.js (for assets)
    if ! command_exists node; then
        log_error "Node.js is not installed. Required for asset compilation"
        exit 1
    fi
    
    log_success "System requirements check completed"
}

# Install Hex and Rebar
setup_elixir_tools() {
    log_info "Setting up Elixir tools..."
    
    mix local.hex --force
    mix local.rebar --force
    
    log_success "Hex and Rebar installed"
}

# Install dependencies
install_dependencies() {
    log_info "Installing Elixir dependencies..."
    
    mix deps.get
    
    log_success "Dependencies installed"
}

# Setup database
setup_database() {
    log_info "Setting up database..."
    
    # Check if database exists
    if mix ecto.create 2>/dev/null; then
        log_success "Database created"
    else
        log_info "Database already exists"
    fi
    
    # Run migrations
    mix ecto.migrate
    
    # Run seeds if they exist
    if [ -f "priv/repo/seeds.exs" ]; then
        mix run priv/repo/seeds.exs
        log_success "Database seeded"
    fi
    
    log_success "Database setup completed"
}

# Setup assets
setup_assets() {
    log_info "Setting up frontend assets..."
    
    # Install Tailwind and esbuild if not present
    mix assets.setup
    
    # Build assets
    mix assets.build
    
    log_success "Assets compiled successfully"
}

# Generate documentation
generate_docs() {
    log_info "Generating project documentation..."
    
    if mix docs 2>/dev/null; then
        log_success "Documentation generated in doc/ directory"
    else
        log_warning "Documentation generation failed - continuing anyway"
    fi
}

# Run tests
run_tests() {
    log_info "Running test suite to verify installation..."
    
    # Create test database
    MIX_ENV=test mix ecto.create --quiet
    MIX_ENV=test mix ecto.migrate --quiet
    
    # Run tests
    if mix test; then
        log_success "All tests passed!"
    else
        log_warning "Some tests failed - check your configuration"
    fi
}

# Setup development tools
setup_dev_tools() {
    log_info "Setting up development tools..."
    
    # Compile project
    mix compile
    
    # Check for security vulnerabilities
    if command_exists mix && mix help sobelow >/dev/null 2>&1; then
        mix sobelow --config
        log_success "Security scan completed"
    fi
    
    # Check code quality
    if command_exists mix && mix help credo >/dev/null 2>&1; then
        mix credo --strict
        log_success "Code quality check completed"
    fi
}

# Create necessary directories
create_directories() {
    log_info "Creating necessary directories..."
    
    mkdir -p tmp/cache
    mkdir -p priv/static
    mkdir -p uploads
    mkdir -p logs
    
    log_success "Directories created"
}

# Setup environment file
setup_environment() {
    log_info "Setting up environment configuration..."
    
    if [ ! -f ".env" ]; then
        cat > .env << 'EOF'
# LANG Development Environment Configuration

# Database
DATABASE_URL=ecto://postgres:postgres@localhost/lang_dev
TEST_DATABASE_URL=ecto://postgres:postgres@localhost/lang_test

# Phoenix
SECRET_KEY_BASE=generate_with_mix_phx_gen_secret
LIVE_VIEW_SIGNING_SALT=generate_with_mix_phx_gen_secret

# Redis (optional - for caching)
REDIS_URL=redis://localhost:6379/0

# Text Intelligence Settings
MAX_TEXT_SIZE=1048576
ANALYSIS_TIMEOUT=30000

# Stylometric Analysis
ENABLE_STYLOMETRICS=true
MIN_TEXT_LENGTH=100

# Background Jobs
OBAN_QUEUES=default:10,analysis:5,stylometrics:3

# Development
PHX_HOST=localhost
PHX_PORT=4000
EOF
        
        log_success "Environment file created at .env"
        log_warning "Please update the SECRET_KEY_BASE and LIVE_VIEW_SIGNING_SALT in .env"
        log_info "Run: mix phx.gen.secret to generate secure keys"
    else
        log_info "Environment file already exists"
    fi
}

# Print startup instructions
print_startup_info() {
    echo ""
    log_success "LANG initialization completed successfully!"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Update your .env file with proper SECRET_KEY_BASE:"
    echo "     mix phx.gen.secret"
    echo ""
    echo "  2. Start the development server:"
    echo "     mix phx.server"
    echo ""
    echo "  3. Visit your application:"
    echo "     http://localhost:4000"
    echo ""
    echo -e "${BLUE}Key Features Available:${NC}"
    echo "  • Text Intelligence API at /api/v1/analyze"
    echo "  • Conversation Rehearsal at /api/v1/rehearsal"
    echo "  • Stylometric Analysis at /api/v1/stylometrics"
    echo "  • Live Dashboard at /dev/dashboard"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  • API Docs: docs/API_DOCUMENTATION.md"
    echo "  • Quick Start: docs/QUICKSTART.md"
    echo "  • Features: docs/README.md"
    echo ""
    echo -e "${GREEN}Happy coding with LANG! 🚀${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          LANG Universal Text Intelligence            ║${NC}"
    echo -e "${BLUE}║               Initialization Script                  ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_requirements
    setup_elixir_tools
    create_directories
    setup_environment
    install_dependencies
    setup_database
    setup_assets
    generate_docs
    setup_dev_tools
    run_tests
    
    print_startup_info
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"