#!/usr/bin/env bash
set -e

# ========================================
# PasarGuard Multi-Panel Installer
# ========================================
# This script does NOT modify the original PasarGuard script.
# It wraps around it, allowing multiple panels on one server.
# ========================================

ORIGINAL_SCRIPT_URL="https://raw.githubusercontent.com/PasarGuard/scripts/main/pasarguard.sh"
INSTALL_DIR="/opt"

colorized_echo() {
    local color=$1; local text=$2
    case $color in
        "red")     printf "\e[91m${text}\e[0m\n" ;;
        "green")   printf "\e[92m${text}\e[0m\n" ;;
        "yellow")  printf "\e[93m${text}\e[0m\n" ;;
        "blue")    printf "\e[94m${text}\e[0m\n" ;;
        "magenta") printf "\e[95m${text}\e[0m\n" ;;
        "cyan")    printf "\e[96m${text}\e[0m\n" ;;
        *)         echo "${text}" ;;
    esac
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "This script must be run as root."
        exit 1
    fi
}

show_banner() {
    echo ""
    colorized_echo cyan "╔══════════════════════════════════════════════════╗"
    colorized_echo cyan "║      PasarGuard Multi-Panel Installer            ║"
    colorized_echo cyan "║  Install multiple PasarGuard panels on 1 server  ║"
    colorized_echo cyan "╚══════════════════════════════════════════════════╝"
    echo ""
}

list_installed_panels() {
    colorized_echo blue "Scanning for installed PasarGuard panels..."
    echo ""
    local found=false
    for dir in "$INSTALL_DIR"/*/; do
        local name=$(basename "$dir")
        if [ -f "$dir/.env" ] && [ -f "$dir/docker-compose.yml" ]; then
            if grep -qi "pasarguard\|ghcr.io/pasarguard" "$dir/docker-compose.yml" 2>/dev/null; then
                local port=$(grep -E "^UVICORN_PORT" "$dir/.env" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' "')
                local status="Down"
                if command -v docker >/dev/null 2>&1; then
                    if docker compose -f "$dir/docker-compose.yml" -p "$name" ps -q 2>/dev/null | grep -q .; then
                        status="Up"
                    fi
                fi
                if [ "$status" == "Up" ]; then
                    colorized_echo green "  ● $name (port: ${port:-?}) - Running"
                else
                    colorized_echo yellow "  ○ $name (port: ${port:-?}) - Stopped"
                fi
                found=true
            fi
        fi
    done
    if [ "$found" = false ]; then
        colorized_echo yellow "  No PasarGuard panels found."
    fi
    echo ""
}

get_used_ports() {
    local used_ports=()
    for dir in "$INSTALL_DIR"/*/; do
        if [ -f "$dir/.env" ]; then
            local p=$(grep -E "^UVICORN_PORT" "$dir/.env" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' "')
            [ -n "$p" ] && used_ports+=("$p")
            if [ -f "$dir/docker-compose.yml" ]; then
                local db_ports=$(grep -E '^\s+- "[0-9]+:' "$dir/docker-compose.yml" 2>/dev/null | grep -oP '"\K[0-9]+(?=:)')
                for dp in $db_ports; do
                    used_ports+=("$dp")
                done
            fi
        fi
    done
    echo "${used_ports[@]}"
}

is_port_available() {
    local port=$1
    local used_ports=($(get_used_ports))
    
    for up in "${used_ports[@]}"; do
        if [ "$up" == "$port" ]; then
            return 1
        fi
    done
    
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            return 1
        fi
    fi
    
    return 0
}

validate_app_name() {
    local name=$1
    
    if [[ -z "$name" ]]; then
        colorized_echo red "Name cannot be empty."
        return 1
    fi
    
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        colorized_echo red "Name must start with a letter, only letters/numbers/dash/underscore allowed."
        return 1
    fi
    
    if [[ ${#name} -gt 50 ]]; then
        colorized_echo red "Name too long (max 50 characters)."
        return 1
    fi
    
    return 0
}

download_original_script() {
    local target_path=$1
    colorized_echo blue "Downloading original PasarGuard script..."
    
    if ! curl -sSL "$ORIGINAL_SCRIPT_URL" -o "$target_path"; then
        colorized_echo red "Failed to download PasarGuard script."
        colorized_echo red "URL: $ORIGINAL_SCRIPT_URL"
        exit 1
    fi
    
    chmod +x "$target_path"
    colorized_echo green "Script downloaded successfully."
}

patch_script_for_panel() {
    local script_path=$1
    local app_name=$2
    local panel_port=$3
    local db_port=$4
    local database_type=$5
    
    colorized_echo blue "Patching script for panel: $app_name"
    
    sed -i "s|^APP_NAME=\"pasarguard\"|APP_NAME=\"${app_name}\"|g" "$script_path"
    
    sed -i "s|^APP_NAME=\${APP_NAME:-\"pasarguard\"}|APP_NAME=\${APP_NAME:-\"${app_name}\"}|g" "$script_path"
    
    sed -i "s|/opt/pasarguard|/opt/${app_name}|g" "$script_path"
    sed -i "s|/var/lib/pasarguard|/var/lib/${app_name}|g" "$script_path"
    
    sed -i "s|COMPOSE_FILE=\"/opt/pasarguard/docker-compose.yml\"|COMPOSE_FILE=\"/opt/${app_name}/docker-compose.yml\"|g" "$script_path"
    sed -i "s|ENV_FILE=\"/opt/pasarguard/.env\"|ENV_FILE=\"/opt/${app_name}/.env\"|g" "$script_path"
    
    colorized_echo green "Script patched for: $app_name"
}


post_install_patch() {
    local app_name=$1
    local panel_port=$2
    local db_port=$3
    local database_type=$4
    local app_dir="/opt/$app_name"
    local env_file="$app_dir/.env"
    local compose_file="$app_dir/docker-compose.yml"
    local data_dir="/var/lib/$app_name"
    
    if [ -f "$env_file" ]; then
        colorized_echo blue "Patching .env for port $panel_port..."
        
        if grep -q "^UVICORN_PORT" "$env_file"; then
            sed -i "s|^UVICORN_PORT.*|UVICORN_PORT = ${panel_port}|" "$env_file"
        else
            echo "UVICORN_PORT = ${panel_port}" >> "$env_file"
        fi
        
        if [ "$database_type" != "sqlite" ] && [ -n "$db_port" ]; then
            sed -i "s|@127\.0\.0\.1:[0-9]*/|@127.0.0.1:${db_port}/|g" "$env_file"
            sed -i "s|@localhost:[0-9]*/|@localhost:${db_port}/|g" "$env_file"
        fi

        colorized_echo green ".env patched."
    fi
    
    if [ -f "$compose_file" ]; then
        colorized_echo blue "Patching docker-compose.yml..."
        
        if [ "$database_type" != "sqlite" ] && [ -n "$db_port" ]; then
            sed -i "s|\"3306:3306\"|\"${db_port}:3306\"|g" "$compose_file"
            sed -i "s|\"5432:5432\"|\"${db_port}:5432\"|g" "$compose_file"
            sed -i "s|3306:3306|${db_port}:3306|g" "$compose_file"
            sed -i "s|5432:5432|${db_port}:5432|g" "$compose_file"
        fi
        
        sed -i "s|/var/lib/pasarguard|${data_dir}|g" "$compose_file"
        
        colorized_echo green "docker-compose.yml patched."
    fi
}

# ========================================
# Install new panel
# ========================================

install_new_panel() {
    local app_name=""
    local panel_port=""
    local db_port=""
    local database_type=""
    local extra_args=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)        app_name="$2"; shift 2 ;;
            --panel-port)  panel_port="$2"; shift 2 ;;
            --db-port)     db_port="$2"; shift 2 ;;
            --database)    database_type="$2"; shift 2 ;;
            *)             extra_args+=("$1"); shift ;;
        esac
    done
    
    if [ -z "$app_name" ]; then
        echo ""
        colorized_echo cyan "Choose a unique name for this panel instance."
        colorized_echo cyan "This name will be used as the service name and CLI command."
        colorized_echo cyan "Examples: panel1, mypanel, pasarguard2"
        echo ""
        while true; do
            read -p "Panel name: " app_name
            if validate_app_name "$app_name"; then
                if [ -d "/opt/$app_name" ]; then
                    colorized_echo yellow "Warning: /opt/$app_name already exists."
                    read -p "Override? (y/n): " override
                    [[ $override =~ ^[Yy]$ ]] && break
                else
                    break
                fi
            fi
        done
    fi
    
    if [ -z "$panel_port" ]; then
        echo ""
        colorized_echo cyan "Used ports on this server:"
        local used=($(get_used_ports))
        if [ ${#used[@]} -gt 0 ]; then
            colorized_echo yellow "  ${used[*]}"
        else
            colorized_echo green "  None"
        fi
        echo ""
        
        local suggest=8000
        while ! is_port_available $suggest; do
            suggest=$((suggest + 1))
        done
        
        while true; do
            read -p "Panel port (suggested: $suggest): " panel_port
            panel_port="${panel_port:-$suggest}"
            
            if [[ ! "$panel_port" =~ ^[0-9]+$ ]] || [ "$panel_port" -lt 1 ] || [ "$panel_port" -gt 65535 ]; then
                colorized_echo red "Invalid port number."
                continue
            fi
            
            if ! is_port_available "$panel_port"; then
                colorized_echo red "Port $panel_port is already in use!"
                continue
            fi
            
            break
        done
    fi
    
    if [ -z "$database_type" ]; then
        echo ""
        colorized_echo cyan "Select database type:"
        echo "  1) SQLite (default, no extra port needed)"
        echo "  2) MariaDB"
        echo "  3) MySQL"
        echo ""
        read -p "Choice (1-3, default: 1): " db_choice
        case "${db_choice:-1}" in
            1) database_type="sqlite" ;;
            2) database_type="mariadb" ;;
            3) database_type="mysql" ;;
            *) database_type="sqlite" ;;
        esac
    fi
    
    if [ "$database_type" != "sqlite" ] && [ -z "$db_port" ]; then
        local db_suggest=3306
        while ! is_port_available $db_suggest; do
            db_suggest=$((db_suggest + 1))
        done
        
        while true; do
            read -p "Database port (suggested: $db_suggest): " db_port
            db_port="${db_port:-$db_suggest}"
            
            if [[ ! "$db_port" =~ ^[0-9]+$ ]]; then
                colorized_echo red "Invalid port."
                continue
            fi
            
            if ! is_port_available "$db_port"; then
                colorized_echo red "Port $db_port is already in use!"
                continue
            fi
            
            if [ "$db_port" == "$panel_port" ]; then
                colorized_echo red "DB port cannot be same as panel port!"
                continue
            fi
            
            break
        done
    fi
    
    # Summary
    echo ""
    colorized_echo blue "═══════════════════════════════════════"
    colorized_echo blue " Installation Summary"
    colorized_echo blue "═══════════════════════════════════════"
    colorized_echo cyan "  Panel Name:     $app_name"
    colorized_echo cyan "  Panel Port:     $panel_port"
    colorized_echo cyan "  Database:       $database_type"
    if [ "$database_type" != "sqlite" ]; then
        colorized_echo cyan "  DB Port:        $db_port"
    fi
    colorized_echo cyan "  App Directory:  /opt/$app_name"
    colorized_echo cyan "  Data Directory: /var/lib/$app_name"
    colorized_echo cyan "  CLI Command:    $app_name"
    colorized_echo blue "═══════════════════════════════════════"
    echo ""
    read -p "Proceed with installation? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        colorized_echo red "Aborted."
        exit 0
    fi
    
    local temp_script="/tmp/pasarguard_original_$$.sh"
    download_original_script "$temp_script"
    
    patch_script_for_panel "$temp_script" "$app_name" "$panel_port" "$db_port" "$database_type"
    
    local cli_path="/usr/local/bin/$app_name"
    cp "$temp_script" "$cli_path"
    chmod 755 "$cli_path"
    colorized_echo green "CLI command installed: $app_name"
    
    local install_args=()
    
    if [ "$database_type" != "sqlite" ]; then
        install_args+=(--database "$database_type")
    fi
    
    for arg in "${extra_args[@]}"; do
        install_args+=("$arg")
    done
    
    colorized_echo blue "Running $app_name install..."
    echo ""
    
    export APP_NAME="$app_name"
    "$cli_path" install "${install_args[@]}"
    
    post_install_patch "$app_name" "$panel_port" "$db_port" "$database_type"
    
    colorized_echo blue "Restarting $app_name with final configuration..."
    "$cli_path" restart -n 2>/dev/null || true
    
    echo ""
    colorized_echo green "═══════════════════════════════════════"
    colorized_echo green " Installation Complete!"
    colorized_echo green "═══════════════════════════════════════"
    colorized_echo cyan "  Panel: $app_name"
    colorized_echo cyan "  URL: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):$panel_port"
    colorized_echo cyan "  Manage: $app_name help"
    colorized_echo green "═══════════════════════════════════════"
    
    rm -f "$temp_script"
}

# ========================================
# Manage existing panel
# ========================================

manage_panel() {
    list_installed_panels
    
    read -p "Enter panel name to manage (or 'q' to quit): " panel_name
    [[ "$panel_name" == "q" ]] && exit 0
    
    if [ ! -f "/usr/local/bin/$panel_name" ]; then
        colorized_echo red "Panel '$panel_name' not found."
        colorized_echo yellow "Make sure the CLI command exists at /usr/local/bin/$panel_name"
        exit 1
    fi
    
    echo ""
    colorized_echo cyan "You can now use: $panel_name <command>"
    colorized_echo cyan "Run '$panel_name help' to see all commands."
    echo ""
    "$panel_name" help
}

# ========================================
# Main Menu
# ========================================

main() {
    check_running_as_root
    show_banner
    
    if [ $# -gt 0 ]; then
        case "$1" in
            install)
                shift
                install_new_panel "$@"
                ;;
            list)
                list_installed_panels
                ;;
            manage)
                shift
                if [ -n "$1" ]; then
                    local panel_name="$1"
                    shift
                    if [ -f "/usr/local/bin/$panel_name" ]; then
                        "$panel_name" "$@"
                    else
                        colorized_echo red "Panel '$panel_name' not found."
                        exit 1
                    fi
                else
                    manage_panel
                fi
                ;;
            help|--help|-h)
                show_help
                ;;
            *)
                show_help
                ;;
        esac
        return
    fi
    
    while true; do
        echo ""
        colorized_echo cyan "What would you like to do?"
        echo ""
        echo "  1) Install a new PasarGuard panel"
        echo "  2) List installed panels"
        echo "  3) Manage an existing panel"
        echo "  4) Help"
        echo "  0) Exit"
        echo ""
        read -p "Choice: " main_choice
        
        case $main_choice in
            1) install_new_panel ;;
            2) list_installed_panels ;;
            3) manage_panel ;;
            4) show_help ;;
            0) colorized_echo green "Bye!"; exit 0 ;;
            *) colorized_echo red "Invalid choice." ;;
        esac
    done
}

show_help() {
    echo ""
    colorized_echo blue "═══════════════════════════════════════════════"
    colorized_echo blue " PasarGuard Multi-Panel - Help"
    colorized_echo blue "═══════════════════════════════════════════════"
    echo ""
    colorized_echo cyan "Usage:"
    echo "  bash install.sh                    Interactive menu"
    echo "  bash install.sh install [options]  Install new panel"
    echo "  bash install.sh list               List installed panels"
    echo "  bash install.sh manage <name>      Manage a panel"
    echo ""
    colorized_echo cyan "Install Options:"
    echo "  --name <name>          Panel name (required for non-interactive)"
    echo "  --panel-port <port>    Panel web port"
    echo "  --database <type>      sqlite | mariadb | mysql"
    echo "  --db-port <port>       Database port (for mariadb/mysql)"
    echo "  --version <ver>        PasarGuard version (e.g., v1.0.0)"
    echo "  --dev                  Use development version"
    echo ""
    colorized_echo cyan "Examples:"
    echo ""
    colorized_echo yellow "  # Interactive install:"
    echo "  bash install.sh install"
    echo ""
    colorized_echo yellow "  # Non-interactive install:"
    echo "  bash install.sh install --name panel1 --panel-port 8001 --database sqlite"
    echo "  bash install.sh install --name panel2 --panel-port 8002 --database mariadb --db-port 3307"
    echo "  bash install.sh install --name panel3 --panel-port 8003 --database mysql --db-port 3308"
    echo ""
    colorized_echo yellow "  # After installation, each panel has its own CLI:"
    echo "  panel1 status"
    echo "  panel1 logs"
    echo "  panel1 restart"
    echo "  panel1 backup"
    echo "  panel1 core-update"
    echo "  panel1 node"
    echo "  panel1 tui        # Full TUI interface"
    echo "  panel1 help       # All original PasarGuard commands"
    echo ""
    colorized_echo yellow "  # Manage via this script:"
    echo "  bash install.sh manage panel1 status"
    echo "  bash install.sh manage panel1 restart"
    echo ""
    colorized_echo cyan "All original PasarGuard commands are preserved:"
    echo "  up, down, restart, status, logs, cli, install, update,"
    echo "  uninstall, install-script, backup, backup-service,"
    echo "  core-update, edit, edit-env, node, tui, help"
    echo ""
    colorized_echo blue "═══════════════════════════════════════════════"
}

main "$@"
