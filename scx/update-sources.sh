#!/bin/bash
# ==============================================================================
# scx Source Update Script
# ==============================================================================
# Updates scx source files (from github.com/sched-ext/scx), dependencies, 
# and toolchain components
#
# Usage: update-sources.sh [options]
# Options:
#   --full       Full update including cargo clean and full rebuild
#   --check-only Check what would be updated without making changes
#   --help       Show this help message
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SCX Repository configuration
SCX_REPO="https://github.com/sched-ext/scx.git"
SCX_TEMP_DIR="/tmp/scx_sync_$$"
SCX_SYNC_DIRS=("lib" "rust" "scheds")

# Parse command line arguments
FULL_UPDATE=false
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_UPDATE=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --help)
            head -20 "$0" | tail -n +2
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

cleanup_temp() {
    if [ -d "$SCX_TEMP_DIR" ]; then
        log_info "Cleaning up temporary directory..."
        rm -rf "$SCX_TEMP_DIR"
    fi
}

trap cleanup_temp EXIT

# ==============================================================================
# Main Update Sequence
# ==============================================================================

log_header "SCX Source Update"

# 0. Synchronize SCX sources from upstream repository
log_header "Synchronizing SCX Sources"

log_info "Source repository: $SCX_REPO"
log_info "Directories to sync: ${SCX_SYNC_DIRS[*]}"

if [ "$CHECK_ONLY" = false ]; then
    log_info "Cloning SCX repository (this may take a moment)..."
    if git clone --depth 1 "$SCX_REPO" "$SCX_TEMP_DIR" 2>&1 | grep -v "^Cloning into"; then
        log_success "SCX repository cloned"
    else
        log_warning "Could not clone SCX repository"
        cleanup_temp
        exit 1
    fi
    
    log_info "Updating files from SCX repository..."
    for dir in "${SCX_SYNC_DIRS[@]}"; do
        if [ -d "$SCX_TEMP_DIR/$dir" ]; then
            log_info "  Updating $dir/..."
            rm -rf "$SCRIPT_DIR/$dir"
            cp -r "$SCX_TEMP_DIR/$dir" "$SCRIPT_DIR/$dir"
        else
            log_warning "  Directory $dir not found in SCX repository"
        fi
    done
    
    log_success "SCX sources synchronized"
else
    log_info "[CHECK-ONLY] Would clone and sync SCX sources"
    log_info "  From: $SCX_REPO"
    log_info "  Directories: ${SCX_SYNC_DIRS[*]}"
fi

# 0b. Cleanup unnecessary files (keep only p2dq essentials)
log_header "Cleaning up Unnecessary Files (p2dq Only)"

if [ "$CHECK_ONLY" = false ]; then
    log_info "Removing non-essential schedulers..."
    SCHEDULERS_TO_REMOVE=(
        "scx_beerland" "scx_bpfland" "scx_cake" "scx_chaos" "scx_cosmos"
        "scx_flash" "scx_lavd" "scx_layered" "scx_mitosis" "scx_pandemonium"
        "scx_rustland" "scx_rusty" "scx_tickless"
    )
    for sched in "${SCHEDULERS_TO_REMOVE[@]}"; do
        if [ -d "$SCRIPT_DIR/scheds/rust/$sched" ]; then
            log_info "  Removing $sched..."
            rm -rf "$SCRIPT_DIR/scheds/rust/$sched"
        fi
    done
    log_success "Non-essential schedulers removed"
    
    log_info "Removing non-essential rust components..."
    RUST_COMPONENTS_TO_REMOVE=(
        "scx_bpf_compat" "scx_bpf_unittests" "scx_raw_pmu" "scx_rustland_core" "scx_userspace_arena"
    )
    for component in "${RUST_COMPONENTS_TO_REMOVE[@]}"; do
        if [ -d "$SCRIPT_DIR/rust/$component" ]; then
            log_info "  Removing $component..."
            rm -rf "$SCRIPT_DIR/rust/$component"
        fi
    done
    log_success "Non-essential rust components removed"
    
    log_info "Removing experimental schedulers and vmlinux files..."
    rm -rf "$SCRIPT_DIR/scheds/experimental"
    # Keep scheds/include and scheds/vmlinux structure for build compatibility
    log_success "Experimental files removed"
    
    log_success "Repository cleaned to p2dq essentials only"
else
    log_info "[CHECK-ONLY] Would remove non-essential schedulers and components"
    log_info "  Schedulers: 13 other than p2dq would be removed"
    log_info "  Components: rust tools and experimental code would be cleaned"
fi

# 1. Update Rust toolchain
if [ "$CHECK_ONLY" = false ]; then
    log_info "Updating Rust toolchain..."
    if rustup update; then
        log_success "Rust toolchain updated"
    else
        log_warning "Could not update Rust toolchain (rustup may not be available)"
    fi
else
    log_info "[CHECK-ONLY] Would update Rust toolchain"
fi

# 2. Install/update cargo-edit if needed
if [ "$CHECK_ONLY" = false ]; then
    log_info "Checking for cargo-edit..."
    if ! command -v cargo-upgrade &> /dev/null; then
        log_info "Installing cargo-edit for dependency management..."
        cargo install cargo-edit --quiet 2>/dev/null || log_warning "Could not install cargo-edit"
    fi
else
    log_info "[CHECK-ONLY] Would check/install cargo-edit"
fi

# 3. Update Cargo.lock
log_info "Updating Cargo lock file..."
if [ "$CHECK_ONLY" = true ]; then
    log_info "Would update Cargo dependencies to latest compatible versions"
else
    cargo update
    log_success "Cargo dependencies updated"
fi

# 4. Check for outdated dependencies
if [ "$CHECK_ONLY" = false ]; then
    log_info "Checking for outdated dependencies..."
    if command -v cargo-outdated &> /dev/null; then
        cargo outdated --root-deps-only || true
    else
        log_info "Installing cargo-outdated for version checks..."
        cargo install cargo-outdated --quiet 2>/dev/null || log_warning "Could not install cargo-outdated"
    fi
else
    log_info "[CHECK-ONLY] Would check/install cargo-outdated"
fi

# 5. Update git submodules if present
if [ -f "$SCRIPT_DIR/.gitmodules" ]; then
    log_info "Updating git submodules..."
    if [ "$CHECK_ONLY" = true ]; then
        git config --file .gitmodules --name-only --get-regexp path | while read -r path; do
            log_info "  Submodule: $path"
        done
    else
        git submodule update --init --recursive
        log_success "Git submodules updated"
    fi
fi

# 6. Audit for security vulnerabilities
if [ "$CHECK_ONLY" = false ]; then
    log_info "Auditing dependencies for security issues..."
    if cargo audit --deny warnings 2>/dev/null; then
        log_success "No security vulnerabilities found"
    else
        log_warning "Some potential vulnerabilities detected (review with cargo audit)"
    fi
else
    log_info "[CHECK-ONLY] Would run cargo audit"
fi

# 7. Format and lint checks
log_info "Running format and lint checks..."
if [ "$CHECK_ONLY" = false ]; then
    if cargo fmt --check &> /dev/null; then
        log_success "Code formatting is correct"
    else
        log_warning "Some files need formatting (run 'cargo fmt' to fix)"
    fi
    
    if cargo clippy --all-targets --all-features -- -D warnings &> /dev/null; then
        log_success "Clippy checks passed"
    else
        log_warning "Some clippy warnings detected (run 'cargo clippy' to review)"
    fi
fi

# 8. Full cleanup and rebuild if requested
if [ "$FULL_UPDATE" = true ]; then
    log_info "Performing full cleanup..."
    cargo clean
    log_success "Build artifacts cleaned"
    
    log_info "Building with release profile..."
    if cargo build --release -p scx_p2dq 2>&1 | tail -20; then
        log_success "Build successful"
    else
        log_error "Build failed"
        exit 1
    fi
fi