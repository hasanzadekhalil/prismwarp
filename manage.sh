#!/usr/bin/env bash
# ==============================================================================
# PrismWarp Management CLI
# Author: Khalil Hasanzade
# Repository: https://github.com/hasanzadekhalil/prismwarp
# License: MIT
# ==============================================================================

set -eo pipefail

BOLD=$'\033[1m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
NC=$'\033[0m'

INSTALL_DIR="/etc/prismwarp"
CONFIGS_DIR="${INSTALL_DIR}/configs"
ENV_FILE="${INSTALL_DIR}/prismwarp.env"
WGCF_BIN="/usr/local/bin/wgcf"

log_info()    { echo -e "${CYAN}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[x]${NC} $1"; }

print_help() {
    cat << EOF
${BOLD}PrismWarp Management CLI${NC}
Author: Khalil Hasanzade

Usage: prismwarp <command> [arguments]

Commands:
  status                   Display live status, memory usage, and egress IP of all instances
  test                     Perform connection latency and egress IP verification
  restart [all | <id>]     Restart all instances or a specific instance (e.g., 'prismwarp restart 01')
  start   [all | <id>]     Start all instances or a specific instance
  stop    [all | <id>]     Stop all instances or a specific instance
  add     <count>          Add N additional proxy instances to the active pool
  delete  [all | <id>]     Stop and remove an instance from the pool (e.g., 'prismwarp delete 08')
  prune                    Clean up any incomplete or broken proxy instances
  logs    <id>             Follow live journal logs for an instance (e.g., 'prismwarp logs 01')
  export  <format>         Export proxy endpoints (formats: list, json, 9router)
  help                     Show this help message

EOF
    exit 0
}

check_installed() {
    if [[ ! -d "$CONFIGS_DIR" ]]; then
        log_error "PrismWarp is not installed. Run sudo ./install.sh first."
        exit 1
    fi
}

get_instances() {
    find "$CONFIGS_DIR" -mindepth 1 -maxdepth 1 -type d -name "warp-*" | sort | while read -r dir; do
        if [[ -f "${dir}/wireproxy.conf" ]]; then
            basename "$dir" | sed 's/warp-//'
        fi
    done
}

get_port_for_id() {
    local id="$1"
    local conf="${CONFIGS_DIR}/warp-${id}/wireproxy.conf"
    if [[ -f "$conf" ]]; then
        grep "^BindAddress" "$conf" | cut -d':' -f2 | tr -d ' '
    else
        echo "N/A"
    fi
}

# ------------------------------------------------------------------------------
# Command: status
# ------------------------------------------------------------------------------
cmd_status() {
    check_installed
    echo -e "${BOLD}==============================================================================${NC}"
    printf "%-10s %-12s %-12s %-12s %-30s\n" "INSTANCE" "PORT" "STATUS" "MEMORY" "EGRESS IP"
    echo -e "${BOLD}==============================================================================${NC}"

    local total_rss_kb=0
    local active_count=0
    local total_count=0

    while read -r id; do
        [[ -z "$id" ]] && continue
        total_count=$((total_count + 1))
        local port
        port=$(get_port_for_id "$id")
        local unit="prismwarp@${id}.service"

        local state
        state=$(systemctl is-active "$unit" 2>/dev/null || true)
        state="${state:-inactive}"

        local mem_str="0 MB"
        local mem_bytes
        mem_bytes=$(systemctl show "$unit" -p MemoryCurrent 2>/dev/null | cut -d'=' -f2 || echo "0")
        if [[ "$mem_bytes" =~ ^[0-9]+$ ]] && [[ "$mem_bytes" -gt 0 ]]; then
            local mem_mb
            mem_mb=$(awk "BEGIN {printf \"%.1f MB\", $mem_bytes/1048576}")
            mem_str="$mem_mb"
            total_rss_kb=$((total_rss_kb + mem_bytes / 1024))
        fi

        local state_colored
        if [[ "$state" == "active" ]]; then
            state_colored="${GREEN}active${NC}"
            active_count=$((active_count + 1))
        else
            state_colored="${RED}${state}${NC}"
        fi

        # Quick trace test
        local egress_ip="-"
        if [[ "$state" == "active" ]]; then
            egress_ip=$(curl --socks5-hostname "127.0.0.1:${port}" -s --max-time 1.5 "https://cloudflare.com/cdn-cgi/trace" 2>/dev/null | grep "^ip=" | cut -d'=' -f2 || echo "online (cached)")
        fi

        printf "%-10s %-12s %-20b %-12s %-30s\n" "warp-${id}" "${port}" "${state_colored}" "${mem_str}" "${egress_ip}"
    done < <(get_instances)

    echo -e "${BOLD}==============================================================================${NC}"
    local total_mb
    total_mb=$(awk "BEGIN {printf \"%.1f\", $total_rss_kb/1024}")
    echo -e "${BOLD}Active Pools:${NC} ${active_count}/${total_count} instances operational"
    echo -e "${BOLD}Total Pool Memory Consumption:${NC} ${GREEN}${total_mb} MB RAM${NC} (vs ~${total_count}x500MB = $((total_count * 500))MB in Docker!)"
    echo ""
}

# ------------------------------------------------------------------------------
# Command: test
# ------------------------------------------------------------------------------
cmd_test() {
    check_installed
    echo -e "${BOLD}Testing latency and egress for all active proxies...${NC}"
    echo -e "${BOLD}------------------------------------------------------------------------------${NC}"
    printf "%-10s %-10s %-10s %-12s %-32s %-8s\n" "INSTANCE" "PORT" "STATUS" "LATENCY" "EGRESS IP" "COLO"
    echo -e "${BOLD}------------------------------------------------------------------------------${NC}"

    while read -r id; do
        [[ -z "$id" ]] && continue
        local port
        port=$(get_port_for_id "$id")

        local start_ts end_ts latency_ms
        start_ts=$(date +%s%3N)
        local trace_resp
        trace_resp=$(curl --socks5-hostname "127.0.0.1:${port}" -s --max-time 4 "https://cloudflare.com/cdn-cgi/trace" 2>/dev/null || true)
        end_ts=$(date +%s%3N)
        latency_ms=$((end_ts - start_ts))

        if echo "$trace_resp" | grep -q "ip="; then
            local ip colo
            ip=$(echo "$trace_resp" | grep "^ip=" | cut -d'=' -f2)
            colo=$(echo "$trace_resp" | grep "^colo=" | cut -d'=' -f2)
            printf "%-10s %-10s %-18b %-12s %-32s %-8s\n" "warp-${id}" "${port}" "${GREEN}SUCCESS${NC}" "${latency_ms}ms" "${ip}" "${colo}"
        else
            printf "%-10s %-10s %-18b %-12s %-32s %-8s\n" "warp-${id}" "${port}" "${RED}FAILED${NC}" "timeout" "N/A" "N/A"
        fi
    done < <(get_instances)
    echo -e "${BOLD}------------------------------------------------------------------------------${NC}"
}

# ------------------------------------------------------------------------------
# Command: restart, start, stop
# ------------------------------------------------------------------------------
cmd_restart() {
    local target="${1:-all}"
    if [[ "$target" == "all" ]]; then
        log_info "Restarting all PrismWarp instances..."
        while read -r id; do
            [[ -z "$id" ]] && continue
            systemctl restart "prismwarp@${id}"
        done < <(get_instances)
        log_success "All instances restarted."
    else
        local padded_id
        padded_id=$(printf "%02d" "${target#0}")
        log_info "Restarting instance warp-${padded_id}..."
        systemctl restart "prismwarp@${padded_id}"
        log_success "Instance warp-${padded_id} restarted."
    fi
}

cmd_start() {
    local target="${1:-all}"
    if [[ "$target" == "all" ]]; then
        log_info "Starting all PrismWarp instances..."
        while read -r id; do
            [[ -z "$id" ]] && continue
            systemctl start "prismwarp@${id}"
        done < <(get_instances)
        log_success "All instances started."
    else
        local padded_id
        padded_id=$(printf "%02d" "${target#0}")
        systemctl start "prismwarp@${padded_id}"
        log_success "Instance warp-${padded_id} started."
    fi
}

cmd_stop() {
    local target="${1:-all}"
    if [[ "$target" == "all" ]]; then
        log_info "Stopping all PrismWarp instances..."
        while read -r id; do
            [[ -z "$id" ]] && continue
            systemctl stop "prismwarp@${id}"
        done < <(get_instances)
        log_success "All instances stopped."
    else
        local padded_id
        padded_id=$(printf "%02d" "${target#0}")
        systemctl stop "prismwarp@${padded_id}"
        log_success "Instance warp-${padded_id} stopped."
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

# ------------------------------------------------------------------------------
# Command: add
# ------------------------------------------------------------------------------
cmd_add() {
    local add_count="${1:-1}"
    if ! [[ "$add_count" =~ ^[0-9]+$ ]] || [[ "$add_count" -le 0 ]]; then
        log_error "Please provide a valid positive integer of proxies to add."
        exit 1
    fi

    # Find highest existing ID and port
    local max_id=0
    local max_port=40000
    while read -r id; do
        [[ -z "$id" ]] && continue
        local num_id=$((10#$id))
        if [[ $num_id -gt $max_id ]]; then max_id=$num_id; fi
        local p
        p=$(get_port_for_id "$id")
        if [[ "$p" =~ ^[0-9]+$ ]] && [[ $p -gt $max_port ]]; then max_port=$p; fi
    done < <(get_instances)

    log_info "Current pool has ${max_id} instances (Highest port: ${max_port}). Adding ${add_count} new instances..."

    local next_id=$((max_id + 1))
    local next_port=$((max_port + 1))

    for ((i=0; i<add_count; i++)); do
        local curr_id curr_port
        curr_id=$(printf "%02d" "$((next_id + i))")
        curr_port=$((next_port + i))

        local instance_dir="${CONFIGS_DIR}/warp-${curr_id}"
        local conf_file="${instance_dir}/wireproxy.conf"

        log_info "Registering WARP account for warp-${curr_id} (Port ${curr_port})..."
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/prismwarp-add-XXXXXX)
        pushd "$tmp_dir" >/dev/null

        local registered=false
        while [[ "$registered" == false ]]; do
            local reg_out
            set +e
            reg_out=$("$WGCF_BIN" register --accept-tos 2>&1)
            local reg_status=$?
            set -e

            if [[ $reg_status -ne 0 ]] || echo "$reg_out" | grep -qiE "429|Too Many Requests"; then
                log_warn "Cloudflare rate limit (HTTP 429) hit at instance warp-${curr_id}."
                if [[ -t 0 ]]; then
                    read -r -p "Wait 5 minutes for Cloudflare cooldown and retry? [Y/n]: " wait_choice
                    wait_choice="${wait_choice:-Y}"
                    if [[ "$wait_choice" =~ ^[Yy]$ ]]; then
                        cooldown_timer
                        continue
                    else
                        log_info "Stopping pool expansion at current instances."
                        popd >/dev/null
                        rm -rf "$tmp_dir"
                        break 2
                    fi
                else
                    cooldown_timer
                    continue
                fi
            else
                registered=true
            fi
        done

        "$WGCF_BIN" generate >/dev/null 2>&1
        local priv_key pub_key address endpoint
        priv_key=$(grep -m 1 "^PrivateKey" wgcf-profile.conf | awk '{print $3}')
        pub_key=$(grep -m 1 "^PublicKey" wgcf-profile.conf | awk '{print $3}')
        address=$(grep -m 1 "^Address" wgcf-profile.conf | cut -d'=' -f2- | sed 's/^[ \t]*//')
        endpoint=$(grep -m 1 "^Endpoint" wgcf-profile.conf | awk '{print $3}')

        mkdir -p "$instance_dir"
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
BindAddress = 127.0.0.1:${curr_port}
EOF
        chmod 600 "$conf_file"
        popd >/dev/null
        rm -rf "$tmp_dir"

        systemctl enable --now "prismwarp@${curr_id}" >/dev/null 2>&1
        log_success "Instance warp-${curr_id} active on port ${curr_port}"
    done
    log_success "Pool expansion complete. Run 'prismwarp status' to view updated state."
}

# ------------------------------------------------------------------------------
# Command: delete / remove
# ------------------------------------------------------------------------------
cmd_delete() {
    check_installed
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        log_error "Please specify instance ID to delete (e.g., 'prismwarp delete 08') or 'all'."
        exit 1
    fi

    if [[ "$target" == "all" ]]; then
        log_warn "Stopping and deleting all instances..."
        while read -r id; do
            [[ -z "$id" ]] && continue
            systemctl stop "prismwarp@${id}" 2>/dev/null || true
            systemctl disable "prismwarp@${id}" 2>/dev/null || true
            rm -rf "${CONFIGS_DIR}/warp-${id}"
        done < <(get_instances)
        log_success "All instances removed from pool."
    else
        local padded_id
        padded_id=$(printf "%02d" "${target#0}")
        local instance_dir="${CONFIGS_DIR}/warp-${padded_id}"
        if [[ ! -d "$instance_dir" ]]; then
            log_error "Instance warp-${padded_id} not found."
            exit 1
        fi
        log_info "Stopping and removing warp-${padded_id}..."
        systemctl stop "prismwarp@${padded_id}" 2>/dev/null || true
        systemctl disable "prismwarp@${padded_id}" 2>/dev/null || true
        rm -rf "$instance_dir"
        log_success "Instance warp-${padded_id} deleted successfully."
    fi
}

# ------------------------------------------------------------------------------
# Command: prune / clean
# ------------------------------------------------------------------------------
cmd_prune() {
    check_installed
    log_info "Scanning for broken, incomplete, or unconfigured instances..."
    local pruned=0
    find "$CONFIGS_DIR" -mindepth 1 -maxdepth 1 -type d -name "warp-*" | sort | while read -r dir; do
        local id
        id=$(basename "$dir" | sed 's/warp-//')
        if [[ ! -f "${dir}/wireproxy.conf" ]]; then
            log_warn "Found incomplete instance warp-${id} (missing wireproxy.conf). Cleaning up..."
            systemctl stop "prismwarp@${id}" 2>/dev/null || true
            systemctl disable "prismwarp@${id}" 2>/dev/null || true
            rm -rf "$dir"
            pruned=$((pruned + 1))
        fi
    done
    log_success "Prune complete. All incomplete instances removed."
}

# ------------------------------------------------------------------------------
# Command: logs
# ------------------------------------------------------------------------------
cmd_logs() {
    local target="${1:-01}"
    local padded_id
    padded_id=$(printf "%02d" "${target#0}")
    journalctl -u "prismwarp@${padded_id}" -n 50 -f
}

# ------------------------------------------------------------------------------
# Command: export
# ------------------------------------------------------------------------------
cmd_export() {
    check_installed
    local format="${1:-list}"

    case "$format" in
        list)
            while read -r id; do
                [[ -z "$id" ]] && continue
                local port
                port=$(get_port_for_id "$id")
                echo "socks5://127.0.0.1:${port}"
            done < <(get_instances)
            ;;
        json)
            local list=()
            while read -r id; do
                [[ -z "$id" ]] && continue
                local port
                port=$(get_port_for_id "$id")
                list+=("\"socks5://127.0.0.1:${port}\"")
            done < <(get_instances)
            echo "[$(IFS=,; echo "${list[*]}")]"
            ;;
        9router)
            cat << 'HEADER'
{
  "proxyPool": [
HEADER
            local entries=()
            while read -r id; do
                [[ -z "$id" ]] && continue
                local port
                port=$(get_port_for_id "$id")
                entries+=("    {\"url\": \"socks5://127.0.0.1:${port}\", \"name\": \"warp-${id}\"}")
            done < <(get_instances)
            (IFS=,; echo "${entries[*]}")
            cat << 'FOOTER'
  ]
}
FOOTER
            ;;
        *)
            log_error "Unknown export format: $format. Supported formats: list, json, 9router"
            exit 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main Dispatcher
# ------------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        status)         cmd_status "$@" ;;
        test)           cmd_test "$@" ;;
        restart)        cmd_restart "$@" ;;
        start)          cmd_start "$@" ;;
        stop)           cmd_stop "$@" ;;
        add)            cmd_add "$@" ;;
        delete|remove)  cmd_delete "$@" ;;
        prune|clean)    cmd_prune "$@" ;;
        logs)           cmd_logs "$@" ;;
        export)         cmd_export "$@" ;;
        help|-h|--help) print_help ;;
        *)
            log_error "Unknown command: $cmd"
            print_help
            ;;
    esac
}

main "$@"
