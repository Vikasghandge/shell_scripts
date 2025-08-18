#!/bin/bash
set -euo pipefail

# --- [ GLOBALS & COLOR CODES ] ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_DIR="logs"
readonly LOG_FILE="${LOG_DIR}/server_monitor_${TIMESTAMP}.log"
readonly SSH_TIMEOUT=10
readonly PORT_CHECK_TIMEOUT=2

# --- [ SERVER DEFINITIONS ] ---
declare -A SERVERS=(
    ["192.168.1.10"]="DB"
    ["192.168.1.20"]="DB"
    ["192.168.1.30"]="APP"
    ["192.168.1.40"]="REDISKAFKA"
    ["192.168.1.50"]="NEWAPP"
)
declare -A REQUIRED_PACKAGES=(
    ["DB"]="mysql-server dotnet-runtime-6.0 ansible openssh-server"
    ["APP"]="dotnet-runtime-6.0 nginx ansible openssh-server"
    ["REDISKAFKA"]="redis-server openjdk-11-jdk ansible openssh-server"
    ["NEWAPP"]="nodejs npm nginx ansible openssh-server"
)
declare -A PORTS_TO_CHECK=(
    ["mysql"]="3306"
    ["redis"]="6379"
    ["kafka"]="9092"
    ["dotnet"]="5000"
    ["ansible"]="22"
    ["http"]="80"
    ["https"]="443"
    ["nodejs"]="3000"
    ["nginx"]="80"
)

# --- [ CREDENTIALS LOAD ] ---
readonly CREDS_FILE="./configs/server_credentials.conf"
declare -A CREDENTIALS
function load_credentials() {
    [[ ! -f "$CREDS_FILE" ]] && { echo -e "${RED}❌ Credential file not found${NC}"; exit 1; }
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        local ip="${line%%=*}" creds="${line##*=}"
        CREDENTIALS["$ip"]="$creds"
    done < "$CREDS_FILE"
}
load_credentials

# --- [ LOGGING FUNCTION ] ---
function log() {
    local level="$1"; shift
    local msg="$*"; local c
    case "$level" in
      INFO)    c=$BLUE;;
      SUCCESS) c=$GREEN;;
      WARNING) c=$YELLOW;;
      ERROR)   c=$RED;;
      *)       c=$NC;;
    esac
    echo -e "${c}$msg${NC}" | tee -a "$LOG_FILE"
}

# --- [ DEPENDENCY CHECK (LOCAL) ] ---
function check_local_deps() {
    local missing=()
    for dep in sshpass ssh nc; do
        command -v "$dep" >/dev/null || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log ERROR "Script dependencies missing: ${missing[*]}"
        exit 1
    fi
}
function setup_logging() { mkdir -p "$LOG_DIR"; : > "$LOG_FILE"; }
check_local_deps
setup_logging

# --- [ REMOTE EXECUTION/UTILITIES ] ---
function ssh_exec() {
    local ip="$1" cmd="$2"
    local creds="${CREDENTIALS[$ip]}"
    local user="${creds%%:*}" pass="${creds##*:}"
    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ConnectTimeout="$SSH_TIMEOUT" "$user@$ip" "$cmd"
}
function remote_os() {
    local ip="$1"
    ssh_exec "$ip" "awk -F'=' '/^ID=/{print \$2}' /etc/os-release 2>/dev/null" | tr -d '"'
}

function confirm() {
    local prompt="$1"
    local answer
    echo -en "${YELLOW}$prompt [y/N]: ${NC}"
    read -r answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# --- [ REMOTE MONITORING FUNCTIONS ] ---
function check_ssh() { ssh_exec "$1" "echo SSH_OK" 2>/dev/null | grep -q SSH_OK; }

function check_system_health() {
    local ip="$1"
    log INFO "  --- System Health ---"
    log INFO "CPU: $(ssh_exec "$ip" "top -bn1 | grep 'Cpu(s)'")"
    log INFO "Memory: $(ssh_exec "$ip" "free -m | sed -n 2p")"
    log INFO "Disk: $(ssh_exec "$ip" "df -h / | tail -1")"
    log INFO "Uptime: $(ssh_exec "$ip" "uptime -p")"
    log INFO "Root Dir: $(ssh_exec "$ip" "ls -ld /")"
}

function check_and_install_packages() {
    local ip="$1" role="$2"
    log INFO "  --- Package Check & Install ---"
    local os_type="$(remote_os "$ip")"
    if [[ -z "$os_type" ]]; then os_type="unknown"; fi
    log INFO "Detected OS: $os_type"
    local pkgmgr
    case "$os_type" in
        "ubuntu"|"debian") pkgmgr="apt-get install -y" ;;
        "rhel"|"centos"|"rocky") pkgmgr="yum install -y" ;;
        "fedora") pkgmgr="dnf install -y" ;;
        *) pkgmgr="";;
    esac
    local missing_pkgs=()
    for pkg in ${REQUIRED_PACKAGES[$role]}; do
        if ! ssh_exec "$ip" "dpkg -l 2>/dev/null | grep -q $pkg || rpm -q $pkg" >/dev/null; then
            log WARNING "Missing package: $pkg"
            missing_pkgs+=("$pkg")
        else
            log SUCCESS "Installed: $pkg"
        fi
    done
    for pkg in "${missing_pkgs[@]}"; do
        if [[ -n "$pkgmgr" ]] && confirm "Install $pkg on $ip?"; then
            log INFO "Installing $pkg on $ip..."
            if ssh_exec "$ip" "sudo $pkgmgr $pkg"; then
                log SUCCESS "  $pkg installed"
            else
                log ERROR "  Failed to install $pkg"
            fi
        else
            log WARNING "  Skipped install of $pkg"
        fi
    done
}

function check_ports() {
    local ip="$1" role="$2"
    log INFO "  --- Port Check ---"
    declare -a tocheck
    case "$role" in
        "DB") tocheck=("mysql" "ansible" "dotnet");;
        "APP") tocheck=("dotnet" "http" "https" "ansible");;
        "REDISKAFKA") tocheck=("redis" "kafka" "ansible");;
        "NEWAPP") tocheck=("nodejs" "http" "https" "ansible");;
        *) tocheck=("ansible");;
    esac
    for service in "${tocheck[@]}"; do
        local port="${PORTS_TO_CHECK[$service]}"
        if nc -z -w"$PORT_CHECK_TIMEOUT" "$ip" "$port" 2>/dev/null; then
            log SUCCESS "[OPEN] $service ($port)"
        else
            log ERROR "[CLOSED] $service ($port)"
        fi
    done
}

# --- [ MAIN MONITOR FUNCTION ] ---
function monitor_server() {
    local ip="$1" role="$2"
    log INFO "=============================="
    log INFO "Monitoring: $ip ($role)"
    if check_ssh "$ip"; then
        log SUCCESS "SSH OK"
        check_system_health "$ip"
        check_and_install_packages "$ip" "$role"
        check_ports "$ip" "$role"
    else
        log ERROR "SSH FAILED"
    fi
    log INFO "=============================="
}

# --- [ SCRIPT RUN ENTRYPOINT ] ---
for ip in "${!SERVERS[@]}"; do
    if [[ -z "${CREDENTIALS[$ip]:-}" ]]; then
        log ERROR "No credentials for $ip"
        continue
    fi
    monitor_server "$ip" "${SERVERS[$ip]}"
    sleep 2
done
log INFO "Logs written to $LOG_FILE"
