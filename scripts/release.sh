#!/bin/bash

# LANG Release Script for Precompiled NIFs
# This script helps manage the release process for precompiled Rust NIFs

set -e

VERSION=$(grep 'version:' mix.exs | sed 's/.*version: "\(.*\)".*/\1/')
CRATES=("graph_reasoner" "lang_parser" "fs_watcher" "lang_perf" "tree_parser")

echo "🚀 LANG Release Script v$VERSION"
echo "=================================="

# Function to print colored output
print_status() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

# Check if we have the required tools
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v mix &> /dev/null; then
        print_error "mix (Elixir) is required but not installed"
        exit 1
    fi
    
    if ! command -v cargo &> /dev/null; then
        print_error "cargo (Rust) is required but not installed"
        exit 1
    fi
    
    if ! command -v gh &> /dev/null; then
        print_warning "gh (GitHub CLI) not found - manual release upload will be required"
    fi
    
    print_status "Dependencies check complete ✓"
}

# Test all NIFs compile correctly
test_compilation() {
    print_status "Testing NIF compilation..."
    
    for crate in "${CRATES[@]}"; do
        print_status "  Testing $crate..."
        cd "native/$crate"
        
        if ! cargo check --quiet; then
            print_error "Failed to compile $crate"
            exit 1
        fi
        
        cd ../..
    done
    
    print_status "All NIFs compile successfully ✓"
}

# Test Elixir compilation
test_elixir() {
    print_status "Testing Elixir compilation..."
    
    export RUSTLER_PRECOMPILATION_EXAMPLE_BUILD=true
    
    if ! mix deps.get --quiet; then
        print_error "Failed to get dependencies"
        exit 1
    fi
    
    if ! mix compile --warnings-as-errors; then
        print_error "Failed to compile Elixir code"
        exit 1
    fi
    
    print_status "Elixir compilation successful ✓"
    
    unset RUSTLER_PRECOMPILATION_EXAMPLE_BUILD
}

# Run tests
run_tests() {
    print_status "Running tests..."
    
    if ! mix test --quiet; then
        print_error "Tests failed"
        exit 1
    fi
    
    print_status "All tests passed ✓"
}

# Generate checksums for local builds
generate_checksums() {
    print_status "Generating local checksums..."
    
    for crate in "${CRATES[@]}"; do
        checksum_file="checksum-${crate}.exs"
        if [ -f "$checksum_file" ]; then
            print_status "  Checksum file exists for $crate"
        else
            print_warning "  No checksum file for $crate - create $checksum_file"
        fi
    done
}

# Create git tag
create_tag() {
    local tag_name="v$VERSION"
    
    if git rev-parse "$tag_name" >/dev/null 2>&1; then
        print_error "Tag $tag_name already exists"
        exit 1
    fi
    
    print_status "Creating git tag $tag_name..."
    
    git tag -a "$tag_name" -m "Release $VERSION"
    
    print_status "Tag created ✓"
    print_status "Push with: git push origin $tag_name"
}

# Show release instructions
show_instructions() {
    local tag_name="v$VERSION"
    
    echo ""
    echo "🎉 Release preparation complete!"
    echo "================================"
    echo ""
    echo "Next steps:"
    echo "1. Push the tag: git push origin $tag_name"
    echo "2. GitHub Actions will build precompiled NIFs for all platforms"
    echo "3. Once complete, update the base_url in your NIF modules to point to:"
    echo "   https://github.com/nocsi/lang/releases/download/v"
    echo "4. Update the checksum files with real checksums from the release"
    echo ""
    echo "To force local compilation for testing:"
    echo "  export RUSTLER_PRECOMPILATION_EXAMPLE_BUILD=true"
    echo "  mix compile --force"
    echo ""
    echo "GitHub Actions workflow will handle:"
    for crate in "${CRATES[@]}"; do
        echo "  - $crate (5 NIFs: 2.15 + 2.16 across 6 platforms)"
    done
    echo ""
    echo "Total artifacts: $((${#CRATES[@]} * 2 * 6)) precompiled NIFs"
}

# Main execution
main() {
    case "${1:-help}" in
        "check")
            check_dependencies
            test_compilation
            test_elixir
            generate_checksums
            ;;
        "test")
            check_dependencies
            test_compilation
            test_elixir
            run_tests
            ;;
        "tag")
            check_dependencies
            test_compilation
            test_elixir
            run_tests
            create_tag
            show_instructions
            ;;
        "help"|*)
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  check    Check dependencies and compilation"
            echo "  test     Run full test suite"
            echo "  tag      Create release tag (runs tests first)"
            echo "  help     Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  RUSTLER_PRECOMPILATION_EXAMPLE_BUILD=true  Force local compilation"
            ;;
    esac
}

main "$@"