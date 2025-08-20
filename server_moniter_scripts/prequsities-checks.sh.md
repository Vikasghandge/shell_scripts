```
#!/bin/bash
# ============================================================
# Script: Remote Server Monitor with File-Based Credentials
# Purpose:
#   - Connects to remote servers using per-server credential files
#   - Checks required packages (interactive install, auto for dotnet)
#   - Checks open ports and system health
#   - Progress is shown server by server
#   - Logs results to ./logs/server_monitor_<timestamp>.log
# ============================================================

# -----------------------------
# SERVER CREDENTIALS DIR SETUP
# -----------------------------
CRED_DIR="./server_creds"
mkdir -p "$CRED_DIR"
# Each file: ./server_creds/SERVERIP.creds, line 1=username, line 2=password

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
EXECUTED_BY=$(whoami)
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/server_monitor_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

# -----------------------------
# SERVER ROLE Definitions
# -----------------------------
declare -A SERVERS=(
    ["10.10.2.223"]="DB"
    ["10.10.1.230"]="REDISKAFKA"
    ["10.10.2.154"]="APP"
    ["10.10.1.162"]="NEWAPP"
)

# -----------------------------
# REQUIRED PACKAGES per role
# -----------------------------
declare -A REQUIRED_PACKAGES=(
    ["DB"]="mysql dotnet ansible"
    ["REDISKAFKA"]="dotnet ansible unzip rsync sshpass"
    ["APP"]="dotnet ansible"
    ["NEWAPP"]="ansible"
)

# -----------------------------
# IMPORTANT PORTS map
# -----------------------------
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
# HELPER: Load credentials for a server IP from file
#   - $1 is the IP, outputs USERNAME and PASSWORD
# ============================================================
load_credentials() {
    local ip=$1
    local cred_file="$CRED_DIR/$ip.creds"
    if [[ ! -f "$cred_file" ]]; then
        echo -e "${RED}❌ Credentials file not found for $ip. Creating template...${NC}"
        echo -e "username\npassword" > "$cred_file"
        echo "Please edit $cred_file with the correct username (line 1) and password (line 2)." | tee -a "$LOGFILE"
        exit 1
    fi
    # Read lines
    USERNAME=$(sed -n '1p' "$cred_file")
    PASSWORD=$(sed -n '2p' "$cred_file")
}

# Detect OS of server
detect_os() {
    local ip=$1
    load_credentials "$ip"
    os=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $USERNAME@$ip \
        "grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '\"'")
    echo "$os"
}

# Returns install command for package & OS
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

# Check and install if package is missing
check_and_auto_install() {
    local ip=$1
    local pkg=$2

    load_credentials "$ip"
    local os=$(detect_os "$ip")

    echo -e "${BLUE}🔹 [$ip] Checking $pkg on $os...${NC}" | tee -a "$LOGFILE"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no $USERNAME@$ip "command -v $pkg >/dev/null 2>&1"

    if [ $? -eq 0 ]; then
        if [ "$pkg" == "dotnet" ]; then
            VERSION=$(sshpass -p "$PASSWORD" ssh $USERNAME@$ip "dotnet --version 2>/dev/null || echo 'Unknown'")
            echo -e "${GREEN}✅ dotnet installed: version $VERSION${NC}" | tee -a "$LOGFILE"
            if [[ ! "$VERSION" =~ ^8 ]]; then
                echo -e "${YELLOW}⚠️ Updating dotnet to version 8 automatically...${NC}" | tee -a "$LOGFILE"
                INSTALL_CMD=$(get_install_cmd "$os" "$pkg")
                sshpass -p "$PASSWORD" ssh $USERNAME@$ip "echo '$PASSWORD' | sudo -S bash -c \"$INSTALL_CMD\""
            fi
        else
            VERSION=$(sshpass -p "$PASSWORD" ssh $USERNAME@$ip "$pkg --version 2>/dev/null || $pkg -V 2>/dev/null || echo 'Unknown version'")
            echo -e "${GREEN}✅ $pkg already installed: $VERSION${NC}" | tee -a "$LOGFILE"
        fi
    else
        echo -e "${RED}❌ $pkg NOT installed on $ip${NC}" | tee -a "$LOGFILE"
        if [ "$pkg" != "dotnet" ]; then
            read -p "👉 Do you want to install $pkg on $ip? (y/n): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                INSTALL_CMD=$(get_install_cmd "$os" "$pkg")
                if [[ -z "$INSTALL_CMD" ]]; then
                    echo -e "${RED}❌ No install command available for $pkg on $os${NC}" | tee -a "$LOGFILE"
                    return
                fi
                echo -e "${YELLOW}➡️ Installing $pkg on $os...${NC}" | tee -a "$LOGFILE"
                sshpass -p "$PASSWORD" ssh $USERNAME@$ip "echo '$PASSWORD' | sudo -S bash -c \"$INSTALL_CMD\""
            else
                echo -e "${YELLOW}⚠️ Skipped installing $pkg on $ip${NC}" | tee -a "$LOGFILE"
            fi
        else
            INSTALL_CMD=$(get_install_cmd "$os" "$pkg")
            sshpass -p "$PASSWORD" ssh $USERNAME@$ip "echo '$PASSWORD' | sudo -S bash -c \"$INSTALL_CMD\""
        fi
    fi
}

# System health information
check_system_health() {
    local ip=$1
    load_credentials "$ip"
    echo -e "${YELLOW}🩺 System Health for $ip:${NC}" | tee -a "$LOGFILE"
    sshpass -p "$PASSWORD" ssh $USERNAME@$ip "
        echo 'CPU Load:' && uptime
        echo -e '\nMemory Usage:' && free -m
        echo -e '\nDisk Usage:' && df -h /
        echo -e '\nRoot Folder Permissions:' && ls -ld /
    " | tee -a "$LOGFILE"
}

# Check if important ports are open
check_ports() {
    local ip=$1
    echo -e "${YELLOW}🌐 Checking ports on $ip...${NC}" | tee -a "$LOGFILE"
    for name in "${!PORTS_TO_CHECK[@]}"; do
        port="${PORTS_TO_CHECK[$name]}"
        nc -z -w2 $ip $port >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Port $port ($name) is OPEN${NC}" | tee -a "$LOGFILE"
        else
            echo -e "${RED}❌ Port $port ($name) is CLOSED${NC}" | tee -a "$LOGFILE"
        fi
    done
}

# ============================================================
# MAIN EXECUTION LOOP: Check each server
# ============================================================
echo -e "\n${YELLOW}📅 Script started at: $RUN_TIME by user: $EXECUTED_BY${NC}" | tee -a "$LOGFILE"

TOTAL_SERVERS=${#SERVERS[@]}
COUNT=1

for ip in "${!SERVERS[@]}"; do
    role="${SERVERS[$ip]}"
    echo -e "\n${BLUE}🔸 Starting health check for Server $COUNT/$TOTAL_SERVERS → $ip ($role)${NC}" | tee -a "$LOGFILE"

    pkgs="${REQUIRED_PACKAGES[$role]}"
    for pkg in $pkgs; do
        check_and_auto_install "$ip" "$pkg"
    done
    check_ports "$ip"
    check_system_health "$ip"

    echo -e "${GREEN}✔️ Completed health check for Server $COUNT/$TOTAL_SERVERS → $ip ($role)${NC}" | tee -a "$LOGFILE"
    echo "----------------------------------------------------" | tee -a "$LOGFILE"
    ((COUNT++))
done

echo -e "\n${GREEN}✅ All $TOTAL_SERVERS servers checked successfully.${NC}" | tee -a "$LOGFILE"
echo -e "${YELLOW}📁 Log saved: $LOGFILE${NC}"
```






### For Storing creds create dir 
```
mkdir -p ./server_creds

```

for each server creds
```
nano ./server_creds/10.10.2.223.creds

```

```
nano ./server_creds/10.10.1.162.creds

```

```
nano ./server_creds/10.1.2.154.creds

```

```
nano ./server_creds/10.10.2.223.creds

```


## store creds in this formate 
```
arcon
Arc0nUn!x!@#$%!

```
