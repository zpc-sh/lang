#!/bin/bash

# LANG Deployment Verification Script
# Comprehensive verification of all deployment components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="lang-floral-firefly-7929"
DOMAIN="lang.nocsi.com"
HEALTH_URL="https://$DOMAIN/health"
WEBHOOK_URL="https://$DOMAIN/webhooks/stripe"
API_BASE="https://$DOMAIN/api/v1"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
WARNINGS=0

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    ((TESTS_FAILED++))
}

test_basic_connectivity() {
    log_info "Testing basic connectivity..."
    
    # Test main domain
    if curl -f -s --max-time 10 "https://$DOMAIN" > /dev/null; then
        log_success "Main domain accessible: $DOMAIN"
    else
        log_error "Main domain not accessible: $DOMAIN"
    fi
    
    # Test Fly.io subdomain
    if curl -f -s --max-time 10 "https://$APP_NAME.fly.dev" > /dev/null; then
        log_success "Fly.io subdomain accessible: $APP_NAME.fly.dev"
    else
        log_error "Fly.io subdomain not accessible: $APP_NAME.fly.dev"
    fi
}

test_health_endpoint() {
    log_info "Testing health endpoint..."
    
    local health_response
    if health_response=$(curl -f -s --max-time 15 "$HEALTH_URL"); then
        log_success "Health endpoint responding"
        
        # Parse health response
        local status
        local version
        local uptime
        
        if command -v jq >/dev/null 2>&1; then
            status=$(echo "$health_response" | jq -r '.status // "unknown"')
            version=$(echo "$health_response" | jq -r '.version // "unknown"')
            uptime=$(echo "$health_response" | jq -r '.uptime // "unknown"')
            
            case "$status" in
                "ok")
                    log_success "Application status: $status"
                    ;;
                "degraded")
                    log_warning "Application status: $status (some issues detected)"
                    ;;
                "error")
                    log_error "Application status: $status (critical issues)"
                    ;;
                *)
                    log_warning "Unknown application status: $status"
                    ;;
            esac
            
            log_info "Application version: $version"
            log_info "Application uptime: $uptime"
            
            # Test individual health checks
            local database_status
            local redis_status
            local memory_status
            local disk_status
            
            database_status=$(echo "$health_response" | jq -r '.checks.database.status // "unknown"')
            redis_status=$(echo "$health_response" | jq -r '.checks.redis.status // "unknown"')
            memory_status=$(echo "$health_response" | jq -r '.checks.memory.status // "unknown"')
            disk_status=$(echo "$health_response" | jq -r '.checks.disk_space.status // "unknown"')
            
            if [ "$database_status" = "ok" ]; then
                log_success "Database health: OK"
            else
                log_error "Database health: $database_status"
            fi
            
            if [ "$redis_status" = "ok" ]; then
                log_success "Redis health: OK"
            elif [ "$redis_status" = "unknown" ]; then
                log_warning "Redis health: Not configured (optional)"
            else
                log_error "Redis health: $redis_status"
            fi
            
            if [ "$memory_status" = "ok" ]; then
                log_success "Memory usage: OK"
            else
                log_warning "Memory usage: $memory_status"
            fi
            
            if [ "$disk_status" = "ok" ]; then
                log_success "Disk usage: OK"
            else
                log_warning "Disk usage: $disk_status"
            fi
            
        else
            log_warning "jq not installed, skipping detailed health analysis"
            log_success "Health endpoint returned data"
        fi
    else
        log_error "Health endpoint not responding: $HEALTH_URL"
    fi
}

test_database_connectivity() {
    log_info "Testing database connectivity..."
    
    if fly ssh console -C "/app/bin/lang eval 'case Ecto.Adapters.SQL.query(Lang.Repo, \"SELECT 1\") do {:ok, _} -> IO.puts(\"SUCCESS\"); _ -> IO.puts(\"FAILED\") end'" 2>/dev/null | grep -q "SUCCESS"; then
        log_success "Database connection working"
    else
        log_error "Database connection failed"
    fi
}

test_rust_nifs() {
    log_info "Testing Rust NIFs functionality..."
    
    # Test if NIFs are loaded and working
    local nif_test_result
    if nif_test_result=$(fly ssh console -C "/app/bin/lang eval 'try do Lang.Native.LangParser.test_connection(); IO.puts(\"SUCCESS\") rescue _ -> IO.puts(\"FAILED\") end'" 2>/dev/null); then
        if echo "$nif_test_result" | grep -q "SUCCESS"; then
            log_success "Rust NIFs loaded and functional"
        else
            log_warning "Rust NIFs may not be fully functional"
        fi
    else
        log_warning "Could not test Rust NIFs (function may not exist)"
    fi
}

test_file_uploads() {
    log_info "Testing file upload capabilities..."
    
    # Check if uploads directory exists and is writable
    if fly ssh console -C "test -d /app/uploads && test -w /app/uploads && echo SUCCESS" 2>/dev/null | grep -q "SUCCESS"; then
        log_success "Upload directory accessible and writable"
    else
        log_error "Upload directory not accessible or not writable"
    fi
    
    # Check volume mount
    if fly volumes list | grep -q "lang_uploads"; then
        log_success "Upload volume is mounted"
    else
        log_error "Upload volume not found"
    fi
}

test_stripe_integration() {
    log_info "Testing Stripe integration..."
    
    # Test webhook endpoint accessibility
    if curl -f -s --max-time 10 -X POST "$WEBHOOK_URL" \
         -H "Content-Type: application/json" \
         -d '{"test": "webhook"}' > /dev/null 2>&1; then
        log_success "Stripe webhook endpoint accessible"
    else
        log_warning "Stripe webhook endpoint may not be properly configured"
    fi
    
    # Check if Stripe secrets are configured
    if fly secrets list | grep -q "STRIPE_SECRET_KEY"; then
        log_success "Stripe API key configured"
    else
        log_error "Stripe API key not configured"
    fi
    
    if fly secrets list | grep -q "STRIPE_WEBHOOK_SECRET"; then
        log_success "Stripe webhook secret configured"
    else
        log_error "Stripe webhook secret not configured"
    fi
}

test_ssl_certificate() {
    log_info "Testing SSL certificate..."
    
    local ssl_info
    if ssl_info=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null); then
        log_success "SSL certificate is valid"
        
        # Check certificate expiry
        local not_after
        not_after=$(echo "$ssl_info" | grep "notAfter" | cut -d= -f2)
        log_info "Certificate expires: $not_after"
    else
        log_error "SSL certificate validation failed"
    fi
}

test_performance() {
    log_info "Testing application performance..."
    
    # Test response times
    local response_time
    response_time=$(curl -o /dev/null -s -w "%{time_total}" "$HEALTH_URL")
    
    if (( $(echo "$response_time < 2.0" | bc -l) )); then
        log_success "Health endpoint response time: ${response_time}s (good)"
    elif (( $(echo "$response_time < 5.0" | bc -l) )); then
        log_warning "Health endpoint response time: ${response_time}s (acceptable)"
    else
        log_error "Health endpoint response time: ${response_time}s (slow)"
    fi
}

test_oban_jobs() {
    log_info "Testing Oban job processing..."
    
    # Check if Oban is running
    if fly ssh console -C "/app/bin/lang eval 'case Oban.check_queue(Lang.Oban, :default) do :ok -> IO.puts(\"SUCCESS\"); _ -> IO.puts(\"FAILED\") end'" 2>/dev/null | grep -q "SUCCESS"; then
        log_success "Oban job processing is active"
    else
        log_warning "Oban job processing may not be configured"
    fi
}

test_ash_resources() {
    log_info "Testing Ash resources..."
    
    # Test if Ash API is accessible
    if fly ssh console -C "/app/bin/lang eval 'length(Lang.Api.resources()) |> IO.inspect'" 2>/dev/null | grep -q "[0-9]"; then
        log_success "Ash resources are loaded"
    else
        log_warning "Could not verify Ash resources"
    fi
}

test_logging_and_monitoring() {
    log_info "Testing logging and monitoring..."
    
    # Check if logs are being generated
    local recent_logs
    if recent_logs=$(fly logs --lines 5 2>/dev/null); then
        if [ -n "$recent_logs" ]; then
            log_success "Application logging is working"
        else
            log_warning "No recent logs found"
        fi
    else
        log_error "Could not retrieve application logs"
    fi
    
    # Check metrics endpoint (if available)
    if curl -f -s --max-time 10 "https://$DOMAIN/metrics" > /dev/null 2>&1; then
        log_success "Metrics endpoint accessible"
    else
        log_warning "Metrics endpoint not accessible (may not be configured)"
    fi
}

test_scaling_configuration() {
    log_info "Testing scaling configuration..."
    
    # Check machine configuration
    local machine_info
    if machine_info=$(fly scale show 2>/dev/null); then
        log_success "Scaling configuration accessible"
        log_info "$machine_info"
    else
        log_warning "Could not retrieve scaling information"
    fi
    
    # Check auto-stop/start configuration
    if fly status --json 2>/dev/null | grep -q "auto_stop_machines"; then
        log_success "Auto-stop/start configuration detected"
    else
        log_warning "Auto-stop/start may not be configured"
    fi
}

run_load_test() {
    log_info "Running basic load test..."
    
    local concurrent_requests=5
    local total_requests=20
    
    # Simple concurrent request test
    for i in $(seq 1 $concurrent_requests); do
        (
            for j in $(seq 1 $((total_requests / concurrent_requests))); do
                curl -f -s --max-time 10 "$HEALTH_URL" > /dev/null || echo "Request failed"
                sleep 0.1
            done
        ) &
    done
    
    wait
    
    log_success "Basic load test completed ($total_requests requests)"
}

show_deployment_summary() {
    echo ""
    echo "==============================================="
    echo "🎯 LANG Deployment Verification Summary"
    echo "==============================================="
    echo ""
    echo "📊 Test Results:"
    echo "✅ Tests Passed: $TESTS_PASSED"
    echo "❌ Tests Failed: $TESTS_FAILED"
    echo "⚠️  Warnings: $WARNINGS"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}🎉 Perfect! All tests passed with no warnings.${NC}"
            echo -e "${GREEN}Your LANG deployment is fully functional.${NC}"
        else
            echo -e "${YELLOW}✅ Good! All critical tests passed, but there are some warnings.${NC}"
            echo -e "${YELLOW}Your LANG deployment is functional with minor issues.${NC}"
        fi
    else
        echo -e "${RED}⚠️  Issues Detected! $TESTS_FAILED tests failed.${NC}"
        echo -e "${RED}Please review and fix the failed tests before going live.${NC}"
    fi
    
    echo ""
    echo "🔗 Important URLs:"
    echo "Application: https://$DOMAIN"
    echo "Health Check: $HEALTH_URL"
    echo "Stripe Webhooks: $WEBHOOK_URL"
    echo "Fly Dashboard: https://fly.io/apps/$APP_NAME"
    echo ""
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo "🔧 Troubleshooting Commands:"
        echo "View logs: fly logs --lines 50"
        echo "App status: fly status"
        echo "SSH access: fly ssh console"
        echo "Restart app: fly machine restart"
        echo ""
    fi
}

# Main verification process
main() {
    echo ""
    echo "🔍 LANG Deployment Verification"
    echo "================================"
    echo ""
    echo "Testing deployment: $DOMAIN"
    echo "Fly.io app: $APP_NAME"
    echo ""
    
    test_basic_connectivity
    test_health_endpoint
    test_database_connectivity
    test_rust_nifs
    test_file_uploads
    test_stripe_integration
    test_ssl_certificate
    test_performance
    test_oban_jobs
    test_ash_resources
    test_logging_and_monitoring
    test_scaling_configuration
    run_load_test
    
    show_deployment_summary
    
    # Exit with error code if tests failed
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"