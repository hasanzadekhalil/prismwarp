#!/usr/bin/env bash
# ==============================================================================
# PrismWarp Uninstaller
# Author: Khalil Hasanzade
# Repository: https://github.com/khasanzade/prismwarp
# License: MIT
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="/etc/prismwarp"
SYSTEMD_UNIT="/etc/systemd/system/prismwarp@.service"
CLI_BIN="/usr/local/bin/prismwarp"
WIREPROXY_BIN="/usr/local/bin/wireproxy"
WGCF_BIN="/usr/local/bin/wgcf"

FORCE=false

log_info()    { echo -e "${CYAN}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[x]${NC} $1"; }

if [[ "$1" == "-y" ]] || [[ "$1" == "--yes" ]]; then
    FORCE=true
fi

if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root or with sudo privileges."
    exit 1
fi

echo -e "${BOLD}PrismWarp Uninstaller${NC}"
echo "This will stop all running PrismWarp proxy instances and remove system configs."
if [[ "$FORCE" == false ]]; then
    read -r -p "Are you sure you want to proceed? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Uninstallation cancelled."
        exit 0
    fi
fi

# 1. Stop and disable all active systemd units
log_info "Stopping and disabling active PrismWarp systemd units..."
active_units=$(systemctl list-units --type=service --state=active 'prismwarp@*' --no-legend 2>/dev/null | awk '{print $1}' || true)
if [[ -n "$active_units" ]]; then
    echo "$active_units" | while read -r unit; do
        [[ -z "$unit" ]] && continue
        log_info "Stopping $unit..."
        systemctl stop "$unit" 2>/dev/null || true
        systemctl disable "$unit" 2>/dev/null || true
    done
fi

# 2. Remove systemd service unit
if [[ -f "$SYSTEMD_UNIT" ]]; then
    log_info "Removing systemd template unit ${SYSTEMD_UNIT}..."
    rm -f "$SYSTEMD_UNIT"
    systemctl daemon-reload
fi

# 3. Remove configurations
if [[ -d "$INSTALL_DIR" ]]; then
    log_info "Removing configuration directory ${INSTALL_DIR}..."
    rm -rf "$INSTALL_DIR"
fi

# 4. Remove CLI management wrapper
if [[ -f "$CLI_BIN" ]]; then
    log_info "Removing CLI binary ${CLI_BIN}..."
    rm -f "$CLI_BIN"
fi

# 5. Remove binaries if requested or clean
if [[ "$FORCE" == false ]]; then
    read -r -p "Do you also want to remove wireproxy and wgcf binaries from /usr/local/bin? [y/N]: " rm_bins
    if [[ "$rm_bins" =~ ^[Yy]$ ]]; then
        rm -f "$WIREPROXY_BIN" "$WGCF_BIN"
        log_success "Binaries removed."
    fi
fi

echo ""
log_success "PrismWarp has been completely uninstalled from this system."
