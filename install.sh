#!/usr/bin/env bash
# ==============================================================================
# PrismWarp: Ultra-lightweight Cloudflare WARP SOCKS5 Multi-Proxy Pool Installer
# Author: Khalil Hasanzade
# Repository: https://github.com/khasanzade/prismwarp
# License: MIT
# ==============================================================================

set -eo pipefail

# Text Formatting
BOLD=$'\033[1m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m' # No Color

# Default Parameters
DEFAULT_COUNT=12
DEFAULT_START_PORT=40001
INSTALL_DIR="/etc/prismwarp"
CONFIGS_DIR="${INSTALL_DIR}/configs"
SYSTEMD_UNIT="/etc/systemd/system/prismwarp@.service"
ENV_FILE="${INSTALL_DIR}/prismwarp.env"
CLI_BIN="/usr/local/bin/prismwarp"
WIREPROXY_BIN="/usr/local/bin/wireproxy"
WGCF_BIN="/usr/local/bin/wgcf"

COUNT=""
START_PORT=""
NON_INTERACTIVE=false

# ------------------------------------------------------------------------------
# Logging Helpers
# ------------------------------------------------------------------------------
log_info()    { echo -e "${CYAN}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[x]${NC} $1"; }

print_banner() {
    cat << "EOF"
  ____       _                 __        __
 |  _ \ _ __(_)___ _ __ ___    \ \      / /_ _ _ __ _ __
 | |_) | '__| / __| '_ ` _ \    \ \ /\ / / _` | '__| '_ \
 |  __/| |  | \__ \ | | | | |    \ V  V / (_| | |  | |_) |
 |_|   |_|  |_|___/_| |_| |_|     \_/\_/ \__,_|_|  | .__/
                                                    |_|
       Ultra-lightweight Cloudflare WARP SOCKS5 Multi-Proxy Pool
       Created by Khalil Hasanzade | MIT License
EOF
    echo ""
}

show_help() {
    echo "Usage: sudo ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --count <NUMBER>       Number of proxy instances to create (default: 12)"
    echo "  -p, --start-port <PORT>    Starting local SOCKS5 port (default: 40001)"
    echo "  -y, --yes                  Run in non-interactive/unattended mode"
    echo "  -h, --help                 Show this help menu"
    echo ""
    exit 0
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--count)
            COUNT="$2"
            shift 2
            ;;
        -p|--start-port)
            START_PORT="$2"
            shift 2
            ;;
        -y|--yes)
            NON_INTERACTIVE=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Pre-Flight Checks
# ------------------------------------------------------------------------------
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root or with sudo privileges."
        exit 1
    fi
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            ARCH_WIREPROXY="linux_amd64"
            ARCH_WGCF="linux_amd64"
            ;;
        aarch64|arm64)
            ARCH_WIREPROXY="linux_arm64"
            ARCH_WGCF="linux_arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch. PrismWarp supports x86_64 and aarch64."
            exit 1
            ;;
    esac
}

install_dependencies() {
    log_info "Verifying system prerequisites..."
    local pkgs=()
    command -v curl >/dev/null 2>&1 || pkgs+=(curl)
    command -v tar >/dev/null 2>&1  || pkgs+=(tar)
    command -v jq >/dev/null 2>&1   || pkgs+=(jq)
    command -v bc >/dev/null 2>&1   || pkgs+=(bc)

    if [[ ${#pkgs[@]} -gt 0 ]]; then
        log_info "Installing required packages: ${pkgs[*]}..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq "${pkgs[@]}" >/dev/null
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q "${pkgs[@]}" >/dev/null
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q "${pkgs[@]}" >/dev/null
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm "${pkgs[@]}" >/dev/null
        else
            log_warn "Package manager not detected. Please ensure ${pkgs[*]} are installed."
        fi
    fi
    log_success "System prerequisites verified."
}

# ------------------------------------------------------------------------------
# Binary Acquisition
# ------------------------------------------------------------------------------
install_binaries() {
    # 1. wireproxy
    if [[ ! -x "$WIREPROXY_BIN" ]]; then
        log_info "Downloading wireproxy binary for ${ARCH_WIREPROXY}..."
        local wp_url="https://github.com/windtf/wireproxy/releases/latest/download/wireproxy_${ARCH_WIREPROXY}.tar.gz"
        local tmp_wp="/tmp/wireproxy.tar.gz"
        curl -fsSL "$wp_url" -o "$tmp_wp"
        tar -xzf "$tmp_wp" -C /tmp/
        mv /tmp/wireproxy "$WIREPROXY_BIN"
        chmod +x "$WIREPROXY_BIN"
        rm -f "$tmp_wp"
        log_success "wireproxy installed to $WIREPROXY_BIN"
    else
        log_success "wireproxy binary already installed at $WIREPROXY_BIN"
    fi

    # 2. wgcf
    if [[ ! -x "$WGCF_BIN" ]]; then
        log_info "Downloading wgcf binary for ${ARCH_WGCF}..."
        local wgcf_tag
        wgcf_tag="$(curl -fsSL https://api.github.com/repos/ViRb3/wgcf/releases/latest | jq -r .tag_name 2>/dev/null || echo "v2.2.22")"
        wgcf_tag="${wgcf_tag#v}"
        local wgcf_url="https://github.com/ViRb3/wgcf/releases/download/v${wgcf_tag}/wgcf_${wgcf_tag}_${ARCH_WGCF}"
        curl -fsSL "$wgcf_url" -o "$WGCF_BIN"
        chmod +x "$WGCF_BIN"
        log_success "wgcf installed to $WGCF_BIN"
    else
        log_success "wgcf binary already installed at $WGCF_BIN"
    fi
}

# ------------------------------------------------------------------------------
# Interactive Prompt
# ------------------------------------------------------------------------------
get_user_input() {
    if [[ "$NON_INTERACTIVE" == true ]]; then
        COUNT="${COUNT:-$DEFAULT_COUNT}"
        START_PORT="${START_PORT:-$DEFAULT_START_PORT}"
        return
    fi

    echo -e "${BOLD}Configuration Setup:${NC}"
    if [[ -z "$COUNT" ]]; then
        read -r -p "Enter number of proxy instances to deploy [default: $DEFAULT_COUNT]: " input_count
        COUNT="${input_count:-$DEFAULT_COUNT}"
    fi

    if [[ -z "$START_PORT" ]]; then
        read -r -p "Enter starting SOCKS5 port [default: $DEFAULT_START_PORT]: " input_port
        START_PORT="${input_port:-$DEFAULT_START_PORT}"
    fi

    echo ""
    log_info "Deployment plan: Deploying ${COUNT} instances on ports ${START_PORT} to $((START_PORT + COUNT - 1))."
    read -r -p "Proceed with installation? [Y/n]: " confirm
    confirm="${confirm:-Y}"
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Installation cancelled by user."
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# Cloudflare 429 Cooldown Timer
# ------------------------------------------------------------------------------
cooldown_timer() {
    local seconds=300
    log_warn "Cloudflare API rate-limit cooldown engaged (5 minutes)."
    echo -e "${CYAN}Waiting for Cloudflare rate limit counter to reset...${NC}"
    while [[ $seconds -gt 0 ]]; do
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        printf "\r${YELLOW}[Cooldown] Time remaining: %02d:%02d...${NC} " "$mins" "$secs"
        sleep 1
        seconds=$((seconds - 1))
    done
    printf "\r${GREEN}[Cooldown] Cooldown completed! Resuming account generation...${NC}\n"
}

handle_rate_limit() {
    local current_idx="$1"
    local total_req="$2"
    log_warn "Cloudflare rate limit (HTTP 429: Too Many Requests) triggered at instance ${current_idx} of ${total_req}."

    if [[ "$NON_INTERACTIVE" == true ]]; then
        log_info "Non-interactive mode: Initiating automated 5-minute cooldown..."
        cooldown_timer
        return 0
    fi

    echo ""
    echo -e "${BOLD}Please choose an action:${NC}"
    echo "  1) Wait 5 minutes with live cooldown timer, then resume automatically"
    echo "  2) Stop generating and finalize installation with the existing $((current_idx - 1)) proxies"
    echo "  3) Abort installation"
    read -r -p "Enter choice [1/2/3]: " choice

    case "$choice" in
        1)
            cooldown_timer
            return 0
            ;;
        2)
            log_warn "Finalizing installation with current $((current_idx - 1)) instances."
            COUNT=$((current_idx - 1))
            return 1 # Stop loop
            ;;
        *)
            log_error "Installation aborted."
            exit 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Account & Wireproxy Generation
# ------------------------------------------------------------------------------
generate_pool() {
    log_info "Initializing PrismWarp directory structure at ${INSTALL_DIR}..."
    mkdir -p "$CONFIGS_DIR"

    local current_port="$START_PORT"
    local created_count=0

    for ((i=1; i<=COUNT; i++)); do
        local id
        id=$(printf "%02d" "$i")
        local instance_dir="${CONFIGS_DIR}/warp-${id}"
        local conf_file="${instance_dir}/wireproxy.conf"

        # If configuration already exists and is valid, reuse it
        if [[ -f "$conf_file" ]] && grep -q "PrivateKey" "$conf_file"; then
            log_success "Instance ${id}: Existing configuration found. Reusing."
            # Ensure port matches intended port
            sed -i "s/BindAddress = 127.0.0.1:.*/BindAddress = 127.0.0.1:${current_port}/" "$conf_file"
            current_port=$((current_port + 1))
            created_count=$((created_count + 1))
            continue
        fi

        mkdir -p "$instance_dir"
        log_info "Instance ${id}/${COUNT}: Registering Cloudflare WARP account..."

        local attempt=0
        local success=false

        while [[ "$success" == false ]]; do
            attempt=$((attempt + 1))
            local tmp_run_dir
            tmp_run_dir="$(mktemp -d /tmp/prismwarp-reg-XXXXXX)"

            pushd "$tmp_run_dir" >/dev/null
            local reg_output
            set +e
            reg_output="$("$WGCF_BIN" register --accept-tos 2>&1)"
            local reg_status=$?
            set -e

            if [[ $reg_status -ne 0 ]] || echo "$reg_output" | grep -qiE "429|Too Many Requests"; then
                popd >/dev/null
                rm -rf "$tmp_run_dir"
                if ! handle_rate_limit "$i" "$COUNT"; then
                    # User chose option 2: finalize current
                    break 2
                fi
                continue
            fi

            # Account registered, now generate wireguard profile
            "$WGCF_BIN" generate >/dev/null 2>&1
            if [[ ! -f "wgcf-profile.conf" ]]; then
                popd >/dev/null
                rm -rf "$tmp_run_dir"
                log_error "Instance ${id}: Failed to generate wgcf-profile.conf."
                exit 1
            fi

            # Parse WireGuard profile keys
            local priv_key pub_key address endpoint
            priv_key=$(grep -m 1 "^PrivateKey" wgcf-profile.conf | awk '{print $3}')
            pub_key=$(grep -m 1 "^PublicKey" wgcf-profile.conf | awk '{print $3}')
            address=$(grep -m 1 "^Address" wgcf-profile.conf | cut -d'=' -f2- | sed 's/^[ \t]*//')
            endpoint=$(grep -m 1 "^Endpoint" wgcf-profile.conf | awk '{print $3}')

            # Generate wireproxy.conf
            cat > "$conf_file" << EOF
[Interface]
PrivateKey = ${priv_key}
Address = ${address}
DNS = 1.1.1.1

[Peer]
PublicKey = ${pub_key}
Endpoint = ${endpoint}
Keepalive = 25

[Socks5]
BindAddress = 127.0.0.1:${current_port}
EOF
            chmod 600 "$conf_file"
            popd >/dev/null
            rm -rf "$tmp_run_dir"
            success=true
            log_success "Instance ${id}: Configured on 127.0.0.1:${current_port}"
        done

        current_port=$((current_port + 1))
        created_count=$((created_count + 1))
    done

    # Save environment state
    cat > "$ENV_FILE" << EOF
# PrismWarp Configuration State
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
INSTANCE_COUNT=${created_count}
START_PORT=${START_PORT}
CONFIGS_DIR=${CONFIGS_DIR}
EOF
}

# ------------------------------------------------------------------------------
# Systemd Deployment
# ------------------------------------------------------------------------------
deploy_systemd() {
    log_info "Deploying systemd service template to ${SYSTEMD_UNIT}..."
    cat > "$SYSTEMD_UNIT" << 'EOF'
[Unit]
Description=PrismWarp Cloudflare SOCKS5 Instance %i
After=network.target network-online.target
Wants=network-online.target
Documentation=https://github.com/khasanzade/prismwarp

[Service]
Type=simple
ExecStart=/usr/local/bin/wireproxy -c /etc/prismwarp/configs/warp-%i/wireproxy.conf
Restart=always
RestartSec=2
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    log_info "Enabling and starting PrismWarp instances..."
    for ((i=1; i<=COUNT; i++)); do
        local id
        id=$(printf "%02d" "$i")
        systemctl enable --now "prismwarp@${id}" >/dev/null 2>&1
    done
    log_success "All ${COUNT} PrismWarp instances activated under systemd."
}

# ------------------------------------------------------------------------------
# CLI Tool Installation
# ------------------------------------------------------------------------------
install_cli() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/manage.sh" ]]; then
        cp "${script_dir}/manage.sh" "$CLI_BIN"
        chmod +x "$CLI_BIN"
        log_success "CLI management tool installed as '${CLI_BIN}'"
    fi
}

# ------------------------------------------------------------------------------
# Post-Installation Self-Test & Diagnostic Table
# ------------------------------------------------------------------------------
run_diagnostics() {
    echo ""
    log_info "Testing proxy pool connectivity and egress IPs..."
    echo -e "${BOLD}------------------------------------------------------------------------------${NC}"
    printf "%-10s %-12s %-10s %-32s %-8s\n" "INSTANCE" "PORT" "STATUS" "EGRESS IP" "COLO"
    echo -e "${BOLD}------------------------------------------------------------------------------${NC}"

    local success_count=0
    for ((i=1; i<=COUNT; i++)); do
        local id
        id=$(printf "%02d" "$i")
        local port=$((START_PORT + i - 1))

        local trace_resp
        trace_resp="$(curl --socks5-hostname "127.0.0.1:${port}" -s --max-time 4 "https://cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)"

        if echo "$trace_resp" | grep -q "ip="; then
            local egress_ip colo
            egress_ip="$(echo "$trace_resp" | grep "^ip=" | cut -d'=' -f2)"
            colo="$(echo "$trace_resp" | grep "^colo=" | cut -d'=' -f2)"
            printf "%-10s %-12s %-18b %-32s %-8s\n" "warp-${id}" "${port}" "${GREEN}ACTIVE${NC}" "${egress_ip}" "${colo}"
            success_count=$((success_count + 1))
        else
            printf "%-10s %-12s %-18b %-32s %-8s\n" "warp-${id}" "${port}" "${RED}FAILED${NC}" "N/A" "N/A"
        fi
    done
    echo -e "${BOLD}------------------------------------------------------------------------------${NC}"
    echo ""

    if [[ "$success_count" -eq "$COUNT" ]]; then
        log_success "Pool Health: 100% Operational (${success_count}/${COUNT} proxies responding)."
    else
        log_warn "Pool Health: ${success_count}/${COUNT} proxies responding. Run 'prismwarp status' for diagnostics."
    fi
}

print_summary() {
    cat << EOF

${GREEN}${BOLD}PrismWarp Deployment Completed Successfully!${NC}

${BOLD}Pool Summary:${NC}
  Total Instances: ${COUNT}
  Port Range:      127.0.0.1:${START_PORT} - 127.0.0.1:$((START_PORT + COUNT - 1))
  Protocol:        SOCKS5 (Userspace WireGuard)
  Configs:         ${CONFIGS_DIR}

${BOLD}Quick Management Commands:${NC}
  prismwarp status        View live health, memory, and IPv6 egress table
  prismwarp test          Test latency and connection on all proxies
  prismwarp restart all   Gracefully restart all proxy instances
  prismwarp export json   Export proxy endpoints for 9router / OmniRoute

EOF
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    print_banner
    check_root
    detect_arch
    install_dependencies
    install_binaries
    get_user_input
    generate_pool
    deploy_systemd
    install_cli
    run_diagnostics
    print_summary
}

main "$@"
