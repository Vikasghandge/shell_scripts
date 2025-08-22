#!/bin/bash
# ============================================================
# Script: Remote Server Monitor with Central Credentials File
# Purpose:
#   - Connects to remote servers using one creds.txt file
#   - Checks required packages (interactive install, auto for dotnet)
#   - Checks open ports and system health
#   - Progress is shown server by server
#   - Logs results to ./logs/server_monitor_<timestamp>.log
# ============================================================

# -----------------------------
# COLORS for output
# -----------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------
# LOGGING setup
# -----------------------------
RUN_TIME=$(date "+%Y-%m-%d %H:%M:%S")
EXECUTED_BY=$(whoami)  # username who is loggin.
LOG_DIR="./logs"  # logs file
mkdir -p "$LOG_DIR"  # logs dir
LOGFILE="$LOG_DIR/server_monitor_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

# -----------------------------
# GLOBAL CREDS
# -----------------------------
CRED_FILE="./creds.txt"    # Create a creds.txt file where add your creds like serverIP, username, and password.
if [[ ! -f "$CRED_FILE" ]]; then
    echo "âŒ Credentials file $CRED_FILE not found. Creating a template..."
    cat <<EOF > "$CRED_FILE"
# Example: IP,username,password
10.10.1.130,mydbuser,mydbpass
10.10.2.153,appuser,apppass
EOF
    echo "Please edit $CRED_FILE with real credentials."
    exit 1
fi

# ============================================================
# HELPER: Load credentials from creds.txt
#   - $1 = Server IP
#   - sets global USERNAME & PASSWORD
# ============================================================
load_credentials() {
    local ip=$1
    local line
    line=$(grep -v '^#' "$CRED_FILE" | grep "^$ip," | head -n1)

    if [[ -z "$line" ]]; then
        echo -e "${RED}âŒ No credentials found for $ip in $CRED_FILE${NC}" | tee -a "$LOGFILE"
        exit 1
    fi

    USERNAME=$(echo "$line" | cut -d',' -f2)
    PASSWORD=$(echo "$line" | cut -d',' -f3)
}

# -----------------------------
# SERVER ROLE Definitions
# -----------------------------
declare -A SERVERS=(
    ["10.10.1.130"]="DB"  
    ["10.10.2.153"]="APP"
    ["10.10.1.228"]="redis/kafka"
   # ["10.10.1.228"]="redis/kafka"
)

# -----------------------------
# REQUIRED PACKAGES per role
# -----------------------------
# below add the packages you want to check according to that server ex. sshpass,ansible,unzip
declare -A REQUIRED_PACKAGES=(
    ["DB"]="mysql dotnet ansible "
    ["APP"]="dotnet ansible sshpass unzip rsync nginx"
    ["redis/kafka"]="mysql dotnet sshpass unzip rsync"
)

# -----------------------------
# IMPORTANT PORTS map
# -----------------------------
# you can customize the ports here as per your need.
declare -A PORTS_TO_CHECK=(
    ["mysql"]=3306
    ["redis"]=6379
    ["kafka"]=9092
    ["dotnet"]=5000
    ["ansible"]=22
    ["http"]=80
    ["https"]=443
)

# ============================================================
# OS detection
# ============================================================
# below script will auto detect the os type and then execute the commands. ex- rhel,ubuntu.
detect_os() {
    local ip=$1
    load_credentials "$ip"
    os=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $USERNAME@$ip \
        "grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '\"'")
    echo "$os"
}

# ============================================================
# Install command builder
# ============================================================
get_install_cmd() {
    local os=$1
    local pkg=$2
    case $pkg in
        dotnet)
            case $os in
                ubuntu|debian)
                    echo "wget https://packages.microsoft.com/config/ubuntu/\$(lsb_release -rs)/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb && \
                          sudo dpkg -i /tmp/packages-microsoft-prod.deb && \
                          sudo apt-get update && \
                          sudo apt-get install -y dotnet-sdk-8.0"
                    ;;
                rhel|centos|rocky|fedora)
                    echo "sudo dnf install -y dotnet-sdk-8.0 || sudo yum install -y dotnet-sdk-8.0"
                    ;;
            esac
            ;;
        mysql)
            [[ "$os" == "ubuntu" || "$os" == "debian" ]] \
                && echo "sudo apt-get update && sudo apt-get install -y mysql-client" \
                || echo "sudo yum install -y mysql"
            ;;
        unzip|rsync|sshpass|ansible)
            [[ "$os" == "ubuntu" || "$os" == "debian" ]] \
                && echo "sudo apt-get update && sudo apt-get install -y $pkg" \
                || echo "sudo yum install -y $pkg"
            ;;
    esac
}

# ============================================================
# Package Checks
# ============================================================
check_and_auto_install() {
    local ip=$1
    local pkg=$2
    load_credentials "$ip"
    local os=$(detect_os "$ip")

    echo -e "${BLUE}ðŸ”¹ [$ip] Checking $pkg on $os...${NC}" | tee -a "$LOGFILE"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $USERNAME@$ip "command -v $pkg >/dev/null 2>&1"

    if [ $? -eq 0 ]; then
        if [ "$pkg" == "dotnet" ]; then
            VERSION=$(sshpass -p "$PASSWORD" ssh $USERNAME@$ip "dotnet --version 2>/dev/null || echo 'Unknown'")
            echo -e "${GREEN}âœ… dotnet installed: version $VERSION${NC}" | tee -a "$LOGFILE"
            if [[ ! "$VERSION" =~ ^8 ]]; then
                echo -e "${YELLOW}âš ï¸ Updating dotnet to version 8 automatically...${NC}" | tee -a "$LOGFILE"
                INSTALL_CMD=$(get_install_cmd "$os" "$pkg")
                sshpass -p "$PASSWORD" ssh $USERNAME@$ip "echo '$PASSWORD' | sudo -S bash -c \"$INSTALL_CMD\""
            fi
        else
            VERSION=$(sshpass -p "$PASSWORD" ssh $USERNAME@$ip "$pkg --version 2>/dev/null || $pkg -V 2>/dev/null || echo 'Unknown version'")
            echo -e "${GREEN}âœ… $pkg already installed: $VERSION${NC}" | tee -a "$LOGFILE"
        fi
    else
        echo -e "${RED}âŒ $pkg NOT installed on $ip${NC}" | tee -a "$LOGFILE"
        if [ "$pkg" != "dotnet" ]; then
            read -p "ðŸ‘‰ Do you want to install $pkg on $ip? (y/n): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                INSTALL_CMD=$(get_install_cmd "$os" "$pkg")
                echo -e "${YELLOW}âž¡ï¸ Installing $pkg on $os...${NC}" | tee -a "$LOGFILE"
                sshpass -p "$PASSWORD" ssh $USERNAME@$ip "echo '$PASSWORD' | sudo -S bash -c \"$INSTALL_CMD\""
            else
                echo -e "${YELLOW}âš ï¸ Skipped installing $pkg on $ip${NC}" | tee -a "$LOGFILE"
            fi
        else
            INSTALL_CMD=$(get_install_cmd "$os" "$pkg")
            sshpass -p "$PASSWORD" ssh $USERNAME@$ip "echo '$PASSWORD' | sudo -S bash -c \"$INSTALL_CMD\""
        fi
    fi
}

# ============================================================
# System health check
# ============================================================
check_system_health() {
    local ip=$1
    load_credentials "$ip"
    echo -e "${YELLOW}ðŸ©º System Health for $ip:${NC}" | tee -a "$LOGFILE"
    sshpass -p "$PASSWORD" ssh $USERNAME@$ip "
        echo 'CPU Load:' && uptime
        echo -e '\nMemory Usage:' && free -m
        echo -e '\nDisk Usage:' && df -h /
        echo -e '\nRoot Folder Permissions:' && ls -ld /
    " | tee -a "$LOGFILE"
}

# ============================================================
# Port check
# ============================================================
check_ports() {
    local ip=$1
    echo -e "${YELLOW}ðŸŒ Checking ports on $ip...${NC}" | tee -a "$LOGFILE"
    for name in "${!PORTS_TO_CHECK[@]}"; do
        port="${PORTS_TO_CHECK[$name]}"
        nc -z -w2 $ip $port >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}âœ… Port $port ($name) is OPEN${NC}" | tee -a "$LOGFILE"
        else
            echo -e "${RED}âŒ Port $port ($name) is CLOSED${NC}" | tee -a "$LOGFILE"
        fi
    done
}

# ============================================================
# MAIN EXECUTION
# ============================================================
echo -e "\n${YELLOW}ðŸ“… Script started at: $RUN_TIME by user: $EXECUTED_BY${NC}" | tee -a "$LOGFILE"

TOTAL_SERVERS=${#SERVERS[@]}
COUNT=1

for ip in "${!SERVERS[@]}"; do
    role="${SERVERS[$ip]}"
    echo -e "\n${BLUE}ðŸ”¸ Starting health check for Server $COUNT/$TOTAL_SERVERS â†’ $ip ($role)${NC}" | tee -a "$LOGFILE"

    pkgs="${REQUIRED_PACKAGES[$role]}"
    for pkg in $pkgs; do
        check_and_auto_install "$ip" "$pkg"
    done
    check_ports "$ip"
    check_system_health "$ip"

    echo -e "${GREEN}âœ”ï¸ Completed health check for Server $COUNT/$TOTAL_SERVERS â†’ $ip ($role)${NC}" | tee -a "$LOGFILE"
    echo "----------------------------------------------------" | tee -a "$LOGFILE"
    ((COUNT++))
done

echo -e "\n${GREEN}âœ… All $TOTAL_SERVERS servers checked successfully.${NC}" | tee -a "$LOGFILE"
echo -e "${YELLOW}ðŸ“ Log saved: $LOGFILE${NC}"

