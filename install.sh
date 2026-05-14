#!/bin/bash
set -e

if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    BLUE=""
    CYAN=""
    GREEN=""
    RED=""
    YELLOW=""
    PURPLE=""
    RESET=""
    BOLD=""
else
    BLUE="\033[34m"
    CYAN="\033[36m"
    GREEN="\033[32m"
    RED="\033[31m"
    YELLOW="\033[33m"
    PURPLE="\033[35m"
    RESET="\033[0m"
    BOLD="\033[1m"
fi

center_title() {
    local title="$1"
    local title_length=${#title}
    local width
    width=$(tput cols 2>/dev/null || echo 50)
    [ "$width" -lt $((title_length + 4)) ] && width=$((title_length + 4))
    local padding=$(( (width - title_length) / 2 ))
    local left_padding
    left_padding=$(printf "%${padding}s" | tr ' ' '-')
    local right_padding
    right_padding=$(printf "%${padding}s" | tr ' ' '-')
    [ $(( (width - title_length) % 2 )) -ne 0 ] && right_padding="${right_padding}-"
    echo "${left_padding}${title}${right_padding}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

run_bg() {
    "$@" &>> "$LOG_FILE" &
    spinner $!
    wait $! || { echo -e "${RED}Error during: $*${RESET}"; echo "See $LOG_FILE for details."; exit 1; }
}

APT="apt-get"
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        APT="sudo apt-get"
    else
        echo -e "${RED}Run as root or install sudo.${RESET}"
        exit 1
    fi
fi

INSTALL_DIR="$HOME/Heroku"
LOG_FILE="/tmp/heroku_installer.log"

clone_or_pull() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo -e "${YELLOW}Heroku directory already exists. Pulling latest...${RESET}"
        run_bg git -C "$INSTALL_DIR" pull
    else
        run_bg git clone https://github.com/coddrago/Heroku "$INSTALL_DIR"
    fi
}

setup_systemd() {
    local exec_start="$1"
    local current_user
    current_user=$(id -un)
    local service_file="/etc/systemd/system/heroku.service"

    cat > "$service_file" <<EOF
[Unit]
Description=Heroku service
After=network.target

[Service]
User=${current_user}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${exec_start}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable heroku
    systemctl restart heroku
    echo -e "${GREEN}Systemd service installed and started.${RESET}"
    echo -e "${CYAN}Logs: journalctl -u heroku -f${RESET}"
}

while true; do
    clear
    echo -e "${PURPLE}${BOLD}"
    curl -fsSL https://raw.githubusercontent.com/coddrago/Heroku/refs/heads/master/assets/download.txt 2>/dev/null || true
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}$(center_title 'Menu')${RESET}"
    echo -e "${BLUE}1. Install Heroku${RESET}"
    echo -e "${BLUE}2. Install Heroku in venv${RESET}"
    echo -e "${BLUE}3. Install Heroku in Docker${RESET}"
    echo -e "${BLUE}4. Install Heroku as systemd service${RESET}"
    echo -e "${BLUE}5. Install Heroku in venv as systemd service${RESET}"
    echo -e "${BLUE}6. Remove Heroku${RESET}"
    echo -e "${BLUE}0. Exit${RESET}"
    echo -e "${CYAN}$(center_title '')${RESET}"
    read -r -p $'\033[33m> \033[0m ' choice

    case $choice in
        1)
            echo -e "${GREEN}Installing Heroku...${RESET}"
            run_bg $APT update
            run_bg $APT install -y git python3 python3-pip
            clone_or_pull
            run_bg pip3 install -r "$INSTALL_DIR/requirements.txt"
            echo -e "${GREEN}Starting Heroku...${RESET}"
            python3 -m heroku --chdir "$INSTALL_DIR"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
        2)
            echo -e "${GREEN}Installing Heroku in venv...${RESET}"
            run_bg $APT update
            run_bg $APT install -y git python3 python3-pip python3-venv
            clone_or_pull
            if [ ! -d "$INSTALL_DIR/.venv" ]; then
                python3 -m venv "$INSTALL_DIR/.venv"
            fi
            run_bg "$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
            echo -e "${GREEN}Starting Heroku...${RESET}"
            "$INSTALL_DIR/.venv/bin/python3" -m heroku --chdir "$INSTALL_DIR"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
        3)
            echo -e "${GREEN}Installing Heroku in Docker...${RESET}"
            run_bg $APT update
            run_bg $APT install -y curl
            bash <(curl -fsSL https://raw.githubusercontent.com/coddrago/Heroku/refs/heads/master/docker.sh)
            echo -e "${GREEN}Completed successfully!${RESET}"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
        4)
            if ! command -v systemctl &>/dev/null; then
                echo -e "${RED}systemd is not available on this system.${RESET}"
                read -r -p $'\033[33mPress Enter to continue... \033[0m'
                continue
            fi
            echo -e "${GREEN}Installing Heroku as systemd service...${RESET}"
            run_bg $APT update
            run_bg $APT install -y git python3 python3-pip
            clone_or_pull
            run_bg pip3 install -r "$INSTALL_DIR/requirements.txt"
            echo -e "${YELLOW}First launch for login (Ctrl+C when done to continue):${RESET}"
            python3 -m heroku --chdir "$INSTALL_DIR" || true
            setup_systemd "$(command -v python3) -m heroku"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
        5)
            if ! command -v systemctl &>/dev/null; then
                echo -e "${RED}systemd is not available on this system.${RESET}"
                read -r -p $'\033[33mPress Enter to continue... \033[0m'
                continue
            fi
            echo -e "${GREEN}Installing Heroku in venv as systemd service...${RESET}"
            run_bg $APT update
            run_bg $APT install -y git python3 python3-pip python3-venv
            clone_or_pull
            if [ ! -d "$INSTALL_DIR/.venv" ]; then
                python3 -m venv "$INSTALL_DIR/.venv"
            fi
            run_bg "$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
            echo -e "${YELLOW}First launch for login (Ctrl+C when done to continue):${RESET}"
            "$INSTALL_DIR/.venv/bin/python3" -m heroku --chdir "$INSTALL_DIR" || true
            setup_systemd "$INSTALL_DIR/.venv/bin/python3 -m heroku"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
        6)
            echo -e "${RED}Removing Heroku...${RESET}"
            if command -v systemctl &>/dev/null; then
                systemctl stop heroku 2>/dev/null || true
                systemctl disable heroku 2>/dev/null || true
                rm -f /etc/systemd/system/heroku.service
                systemctl daemon-reload
            fi
            rm -rf "$INSTALL_DIR"
            docker stop heroku_ub 2>/dev/null || true
            docker rm -f heroku_ub 2>/dev/null || true
            echo -e "${GREEN}Completed successfully!${RESET}"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
        0)
            exit 0
            ;;
        *) 
            echo -e "${RED}Invalid choice!${RESET}"
            read -r -p $'\033[33mPress Enter to continue... \033[0m'
            ;;
    esac
done
