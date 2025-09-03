#!/bin/bash

#===============================================================================
#
#                     DEVELOPMENT ENVIRONMENT SETUP SCRIPT
#                            for AVerMedia AI Fusion Kit
#
#===============================================================================
#
# Description: Automated setup script for AVerMedia AI Fusion Kit development environment
#
# Prerequisites:
#   - Jetson-based AVerMedia device
#   - Internet connectivity
#   - Correct system time
#   - sudo privileges
#
# Usage:
#   sudo ./setup.sh [options]
#
# Options:
#   -h, --help       Show this help message
#   --no-color       Disable colored output
#
#===============================================================================

set -e

readonly DEMO_IMAGE="ghcr.io/avermedia-technologies-inc/ai-fusion-kit-demo:latest"
readonly VLLM_IMAGE="dustynv/vllm:r36.4-cu129-24.04"
readonly DEMO_VLM_MODEL="Qwen/Qwen2.5-VL-3B-Instruct-AWQ"

# Global configuration
USE_COLORS=true

# Step variables
CURRENT_STEP=0
TOTAL_STEPS=8

INTERNET_CONNECTED=false
SYSTEM_TIME_VALID=false
POWER_MODE_SET=false
AVERMEDIA_UDEV_RULES_SET=false
JETPACK_COMPONENTS_ALL_INSTALLED=false
JETPACK_COMPONENTS_NECESSARY_INSTALLED=false
DOCKER_INSTALLED=false
JETSON_CONTAINERS_INSTALLED=false
DEMO_INSTALLED=false

USER_JUST_ADDED_TO_DOCKER_GROUP=false

#===============================================================================
# Utility Functions
#===============================================================================

detect_terminal_width() {
    local width=80

    if command -v tput >/dev/null 2>&1; then
        local tput_width
        tput_width=$(tput cols 2>/dev/null)
        if [ -n "$tput_width" ] && [ "$tput_width" -gt 0 ]; then
            width=$tput_width
        fi
    elif command -v stty >/dev/null 2>&1; then
        local stty_output
        stty_output=$(stty size 2>/dev/null)
        if [ -n "$stty_output" ]; then
            width=$(echo "$stty_output" | cut -d' ' -f2)
        fi
    elif [ -n "$COLUMNS" ]; then
        width=$COLUMNS
    fi

    echo "$width"
}

detect_color_support() {
    if [ "$USE_COLORS" = false ]; then
        return 1
    fi

    # Check if the output is being redirected (not a terminal)
    if [ ! -t 1 ]; then
        return 1
    fi

    # Check NO_COLOR standard
    if [ -n "$NO_COLOR" ]; then
        return 1
    fi

    # Detect with tput
    if command -v tput >/dev/null 2>&1; then
        if [ "$(tput colors 2>/dev/null)" -ge 8 ]; then
            return 0
        fi
    fi

    return 1
}

init_terminal() {
    TERMINAL_WIDTH=$(detect_terminal_width)

    if detect_color_support; then
        readonly RED='\033[0;31m'
        readonly GREEN='\033[0;32m'
        readonly YELLOW='\033[1;33m'
        readonly BLUE='\033[0;34m'
        readonly PURPLE='\033[0;35m'
        readonly CYAN='\033[0;36m'
        readonly WHITE='\033[1;37m'
        readonly BOLD='\033[1m'
        readonly NC='\033[0m'
    else
        readonly RED=''
        readonly GREEN=''
        readonly YELLOW=''
        readonly BLUE=''
        readonly PURPLE=''
        readonly CYAN=''
        readonly WHITE=''
        readonly BOLD=''
        readonly NC=''
    fi

    readonly SUCCESS_SYMBOL="[OK]"
    readonly WARNING_SYMBOL="[WARNING]"
    readonly ERROR_SYMBOL="[ERROR]"
    readonly INFO_SYMBOL="[INFO]"
    readonly BULLET_SYMBOL=" • "
}

print_banner() {
    if [ "$TERMINAL_WIDTH" -ge 80 ]; then
        local banner="\n"
        banner+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        banner+="\n"
        banner+="                         ${BOLD}${WHITE}DEVELOPMENT ENVIRONMENT SETUP${NC}\n"
        banner+="                           ${WHITE}for AVerMedia AI Fusion Kit${NC}\n"
        banner+="\n"
        banner+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        banner+="\n"
        printf "$banner"
    elif [ "$TERMINAL_WIDTH" -ge 60 ]; then
        local banner="\n"
        banner+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        banner+="               ${BOLD}${WHITE}DEVELOPMENT ENVIRONMENT SETUP${NC}\n"
        banner+="                 ${WHITE}for AVerMedia AI Fusion Kit${NC}\n"
        banner+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        banner+="\n"
        printf "$banner"
    else
        local banner="\n"
        banner+="${BOLD}${WHITE}DEVELOPMENT ENVIRONMENT SETUP${NC}\n"
        banner+="${WHITE}for AVerMedia AI Fusion Kit${NC}\n"
        banner+="\n"
        printf "$banner"
    fi
}

print_header() {
    local text="$1"
    local line_char="━"
    local padding=2

    if [ "$TERMINAL_WIDTH" -ge 80 ]; then
        local header=""
        header+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        header+="${BOLD}${WHITE}$(printf "%*s" $padding "")$text${NC}\n"
        header+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "$header"
    elif [ "$TERMINAL_WIDTH" -ge 60 ]; then
        local header=""
        header+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        header+="${BOLD}${WHITE}$(printf "%*s" $padding "")$text${NC}\n"
        header+="${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        printf "$header"
    else
        printf "${BOLD}${WHITE}=== $text ===${NC}\n"
    fi
}

print_step() {
    local format="$1"
    shift
    local text=$(printf "$format" "$@")
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n${BOLD}${CYAN}[%d/%d] %s${NC}\n" "$CURRENT_STEP" "$TOTAL_STEPS" "$text"
}

print_success() {
    local format="$1"
    shift
    local text=$(printf "$format" "$@")
    printf "${GREEN}${SUCCESS_SYMBOL}${NC} %s\n" "$text"
}

print_warning() {
    local format="$1"
    shift
    local text=$(printf "$format" "$@")
    printf "${YELLOW}${WARNING_SYMBOL}${NC} %s\n" "$text"
}

print_error() {
    local format="$1"
    shift
    local text=$(printf "$format" "$@")
    printf "${RED}${ERROR_SYMBOL}${NC} %s\n" "$text"
}

print_info() {
    local format="$1"
    shift
    local text=$(printf "$format" "$@")
    printf "${CYAN}${INFO_SYMBOL}${NC} %s\n" "$text"
}

ask_user() {
    local question="$1"
    local default="$2"
    local response

    while true; do
        printf "${YELLOW}%s${NC}\n" "$question"

        if [ -n "$default" ]; then
            printf "  ${YELLOW}Default: %s${NC}\n" "$default"
            read -p "  Your choice [y/n]: " response
            response=${response:-$default}
        else
            read -p "  Your choice [y/n]: " response
        fi

        case $response in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) printf "  ${RED}Please answer yes (y) or no (n).${NC}\n\n" ;;
        esac
    done
}

show_help() {
    cat << EOF
AVerMedia AI Fusion Kit Development Environment Setup Script

USAGE:
    sudo ./setup.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message and exit
    --no-color      Disable colored output

DESCRIPTION:
    This script automates the setup of AVerMedia AI Fusion Kit development environment.
    It will install and configure:

    ${BULLET_SYMBOL} Docker (with NVIDIA Container Toolkit)
    ${BULLET_SYMBOL} NVIDIA JetPack SDK components
    ${BULLET_SYMBOL} NVIDIA jetson-containers tool
    ${BULLET_SYMBOL} AVerMedia software demo applications and models (optional)

PREREQUISITES:
    ${BULLET_SYMBOL} Jetson-based AVerMedia device
    ${BULLET_SYMBOL} Internet connectivity
    ${BULLET_SYMBOL} Correct system time
    ${BULLET_SYMBOL} sudo privileges

EXAMPLES:
    # Interactive setup
    sudo ./setup.sh

    # Interactive setup without colors (for unsupported terminals)
    sudo ./setup.sh --no-color

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                init_terminal
                show_help
                exit 0
                ;;
            --no-color)
                USE_COLORS=false
                shift
                ;;
            *)
                init_terminal
                printf "${RED}Unknown option: %s${NC}\n" "$1"
                printf "Use --help for usage information.\n"
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# Main Functions
#===============================================================================

detect_l4t_version() {
    L4T_RELEASE=$(head -n 1 /etc/nv_tegra_release | cut -f 2 -d ' ' | grep -Po '(?<=R)\d+')
    local revision=$(head -n 1 /etc/nv_tegra_release | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[0-9.]+')

    if [ -z "$L4T_RELEASE" ] || [ -z "$revision" ]; then
        print_error "Failed to determine L4T version"
        return 1
    fi

    L4T_REVISION_MAJOR=$(echo "$revision" | cut -f 1 -d '.')
    L4T_REVISION_MINOR=$(echo "$revision" | cut -f 2 -d '.')

    L4T_VERSION="$L4T_RELEASE.$L4T_REVISION_MAJOR.$L4T_REVISION_MINOR"
    print_info "Detected L4T version: $L4T_VERSION"

    return 0
}

check_internet() {
    print_info "Checking internet connectivity..."

    # Check with wget
    if command -v wget >/dev/null 2>&1; then
        if wget -q --spider --timeout=10 --tries=1 "https://www.avermedia.com" 2>/dev/null; then
            print_success "Internet connectivity confirmed (via HTTPS)"
            INTERNET_CONNECTED=true
            return 0
        fi
        if wget -q --spider --timeout=10 --tries=1 "https://www.nvidia.com/" 2>/dev/null; then
            print_success "Internet connectivity confirmed (via HTTPS)"
            INTERNET_CONNECTED=true
            return 0
        fi
        if wget -q --spider --timeout=10 --tries=1 "http://www.nvidia.com/" 2>/dev/null; then
            print_success "Internet connectivity confirmed (via HTTP)"
            INTERNET_CONNECTED=true
            return 0
        fi
    fi

    # Try TCP connections with nc
    if command -v nc >/dev/null 2>&1; then
        if timeout 10 nc -z www.nvidia.com 80 >/dev/null 2>&1; then
            print_success "Internet connectivity confirmed (via TCP connection)"
            INTERNET_CONNECTED=true
            return 0
        fi
        if timeout 10 nc -z www.nvidia.com 443 >/dev/null 2>&1; then
            print_success "Internet connectivity confirmed (via TCP connection)"
            INTERNET_CONNECTED=true
            return 0
        fi
    fi

    print_error "No internet connectivity detected"
    printf "  Attempted multiple connection methods:\n"
    printf "    ${BULLET_SYMBOL} HTTPS requests\n"
    printf "    ${BULLET_SYMBOL} TCP connections\n"
    printf "  Please ensure the machine is connected to the internet before continuing.\n"
    return 1
}

get_internet_time() {
    # Try to get actual time from internet sources
    # Using HTTP (not HTTPS) to avoid SSL certificate validation issues when system time is wrong
    if command -v wget >/dev/null 2>&1; then
        for url in "http://www.nvidia.com" "http://www.google.com"; do
            date_header=$(wget -qS --spider --timeout=10 "$url" 2>&1 | grep -i "date:" | head -1 | awk '{for (i=2; i<NF; i++) printf $i " "; print $NF}')
            if [ -n "$date_header" ]; then
                internet_timestamp=$(date -d "$date_header" +%s 2>/dev/null)
                if [ -n "$internet_timestamp" ]; then
                    printf "%s\n" "$internet_timestamp"
                    return 0
                fi
            fi
        done
    fi

    return 1
}

check_time() {
    print_info "Checking system time..."

    current_time=$(date +%s)

    printf "  System time: %s\n" "$(date)"
    print_info "Getting internet time..."
    internet_time=$(get_internet_time)

    # Compare system time with internet time
    if [ -n "$internet_time" ]; then
        time_diff=$((current_time - internet_time))
        abs_time_diff=${time_diff#-}  # Get absolute value

        if [ "$abs_time_diff" -le 300 ]; then
            print_success "System time is accurate (within 5 minutes of internet time)"
            SYSTEM_TIME_VALID=true
            return 0
        else
            if [ "$abs_time_diff" -le 3600 ]; then
                print_warning "System time differs by $(($abs_time_diff / 60)) minutes from internet time"
            else
                print_warning "System time differs by $(($abs_time_diff / 3600)) hours from internet time"
            fi
            printf "  This may cause SSL/TLS certificate validation issues\n"

            if ask_user "Would you like to update the system time to the internet time?"; then
                if sudo date -s "@$internet_time" >/dev/null 2>&1; then
                    print_success "System time updated successfully to: $(date)"
                    SYSTEM_TIME_VALID=true
                    return 0
                else
                    print_error "Failed to update system time"
                    printf "  Possible reasons:\n"
                    printf "    ${BULLET_SYMBOL} Not running with sufficient privileges\n"
                    printf "    ${BULLET_SYMBOL} Invalid timestamp format\n"
                    printf "    ${BULLET_SYMBOL} System protection against time changes\n"
                    if ! ask_user "Do you want to continue anyway?"; then
                        return 1
                    fi
                fi
            else
                if ! ask_user "System time not updated. Do you want to continue anyway?"; then
                    return 1
                fi
            fi
        fi
    else
        print_error "Failed to get internet time"
        if ! ask_user "Do you want to continue anyway?"; then
            return 1
        fi

        # Basic sanity check
        min_time=$(date -d "2025-08-01 00:00:00 UTC" +%s 2>/dev/null)
        max_time=$(date -d "2045-08-01 00:00:00 UTC" +%s 2>/dev/null)

        if [ "$current_time" -lt "$min_time" ] || [ "$current_time" -gt "$max_time" ]; then
            print_error "System time is clearly wrong: $(date)"
            printf "  System time is not within reasonable range (2025-08-01 to 2045-08-01)\n"
            printf "  This may cause SSL/TLS certificate validation failures\n"
            printf "  Please set the correct time before continuing.\n"
            printf "  You can use: ${CYAN}sudo date -s 'YYYY-MM-DD HH:MM:SS'${NC}\n"
            return 1
        fi

        print_warning "Failed to verify system time. If you experience SSL/TLS errors, check if your system time is correct."
    fi

    return 0
}

add_udev_rules() {
    print_info "Adding udev rules for AVerMedia devices..."

    # AS311
    sudo tee /etc/udev/rules.d/70-as311.rules > /dev/null <<EOF
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="07ca", ATTRS{idProduct}=="7310", TAG+="uaccess", SYMLINK+="as311hid"
EOF

    # Reload udev rules
    print_info "Reloading udev rules..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger

    print_success "AVerMedia device udev rules configured"
    AVERMEDIA_UDEV_RULES_SET=true
    return 0
}

install_jetpack() {
    if ! dpkg -l | grep -q "nvidia-jetpack"; then
        print_info "NVIDIA JetPack SDK components have not been installed yet"
        printf "\n"

        if ask_user "Do you want to install all JetPack components now? (If you choose no, only the necessary components for demo applications will be installed)"; then
            print_info "Installing NVIDIA JetPack components..."
            sudo apt-get install -y nvidia-jetpack 2>&1 | sed "s/^/  /"
            print_success "NVIDIA JetPack components installed"
            JETPACK_COMPONENTS_ALL_INSTALLED=true
            JETPACK_COMPONENTS_NECESSARY_INSTALLED=true
        else
            print_info "Skipping full JetPack installation"
            printf "  You can install them later with: ${BOLD}sudo apt install nvidia-jetpack${NC}\n\n"

            print_info "Installing necessary components...\n"
            printf "\n"
            print_info "Installing NVIDIA Container Toolkit..."
            sudo apt-get install -y nvidia-container 2>&1 | sed "s/^/  /"
            print_success "NVIDIA Container Toolkit installed\n"

            print_info "Installing NVIDIA GStreamer plugins..."
            sudo apt-get install -y nvidia-l4t-gstreamer 2>&1 | sed "s/^/  /"
            print_success "NVIDIA GStreamer plugins installed"
            JETPACK_COMPONENTS_NECESSARY_INSTALLED=true
        fi
    else
        print_success "NVIDIA JetPack SDK components already installed"
        JETPACK_COMPONENTS_ALL_INSTALLED=true
        JETPACK_COMPONENTS_NECESSARY_INSTALLED=true
    fi

    return 0
}

install_docker() {
    # Follow the instructions from https://docs.docker.com/engine/install/ubuntu/
    print_info "Installing Docker..."

    print_info "Removing unofficial Docker packages (if any)..."
    sudo apt-get remove docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc &>/dev/null || true

    print_info "Adding Docker's official GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    print_info "Adding Docker's official repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update 2>&1 | sed "s/^/  /"

    # Install Docker
    if [ "$L4T_RELEASE" -le 36 ] && [ "$L4T_REVISION_MAJOR" -le 4 ] && [ "$L4T_REVISION_MINOR" -le 3 ]; then
        print_info "Docker 28 is not compatible with L4T version <= 36.4.3. Installing Docker 27.5..."
        local version="5:27.5.1-1~ubuntu.22.04~jammy"
        local packages="docker-ce=$version docker-ce-cli=$version containerd.io docker-buildx-plugin docker-compose-plugin"
    else
        print_info "Installing the latest version of Docker..."
        local packages="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    fi

    if sudo apt-get install -y --allow-downgrades $packages 2>&1 | sed "s/^/  /"; then
        print_success "Successfully installed Docker packages"
    else
        print_error "Failed to install Docker packages"
        return 1
    fi

    # Configure Docker runtime
    print_info "Configuring Docker runtime with NVIDIA Container Toolkit..."
    sudo nvidia-ctk runtime configure --runtime=docker 2>&1 | sed "s/^/  /"
    sudo jq '. + {"default-runtime": "nvidia"}' /etc/docker/daemon.json | \
        sudo tee /etc/docker/daemon.json.tmp 2>&1 | sed "s/^/  /" && \
        sudo mv /etc/docker/daemon.json.tmp /etc/docker/daemon.json

    # Restart Docker service
    print_info "Restarting Docker service..."
    sudo systemctl daemon-reload 2>&1 | sed "s/^/  /"
    sudo systemctl enable docker 2>&1 | sed "s/^/  /"
    sudo systemctl restart docker 2>&1 | sed "s/^/  /"

    # Test Docker installation
    print_info "Testing Docker installation..."
    if sudo docker run --rm hello-world >/dev/null 2>&1; then
        print_success "Docker is working correctly!"
    else
        print_warning "Docker hello-world test failed. Checking Docker status..."

        if ! sudo systemctl is-active --quiet docker; then
            print_info "Docker service is not running. Attempting to start..."
            if sudo systemctl start docker; then
                print_info "Docker service started. Retrying test..."
                if sudo docker run --rm hello-world >/dev/null 2>&1; then
                    print_success "Docker is now working correctly!"
                else
                    print_error "Docker hello-world test still failing. Manual intervention may be required."
                    return 1
                fi
            else
                print_error "Failed to start Docker service."
                return 1
            fi
        else
            print_error "Docker service is running but test failed"
            printf "  This might be a permission or configuration issue.\n"
            return 1
        fi
    fi
    DOCKER_INSTALLED=true

    # Check if current user should be added to docker group
    if [ -n "$SUDO_USER" ] && ! groups "$SUDO_USER" | grep -q '\bdocker\b'; then
        printf "\n"
        print_info "Adding user %s to docker group..." "$SUDO_USER"
        sudo usermod -aG docker "$SUDO_USER"
        print_success "User added to docker group"
        printf "  ${CYAN}Note:${NC} You may need to log out and back in for group changes to take effect.\n"
        printf "  Alternatively, run: ${CYAN}newgrp docker${NC}\n"
        USER_JUST_ADDED_TO_DOCKER_GROUP=true
    fi

    printf "\n"
    print_success "Docker installation and configuration completed!"
    return 0
}

install_jetson_containers() {
    print_info "Installing jetson-containers framework...\n"

    # Ask for the path to install jetson-containers
    jetson_containers_default_path="/opt/jetson-containers"
    printf "${CYAN}Where do you want to install jetson-containers?${NC}\n"
    printf "${YELLOW}  Default: %s${NC}\n" "$jetson_containers_default_path"
    read -p "  Installation path: " jetson_containers_path
    if [ -z "$jetson_containers_path" ]; then
        jetson_containers_path="$jetson_containers_default_path"
    fi

    # Check if jetson-containers directory exists
    if [ -d "$jetson_containers_path" ]; then
        print_warning "jetson-containers directory already exists"
        print_info "Attempting to update existing installation..."
        if git -C "$jetson_containers_path" pull; then
            print_success "Updated jetson-containers successfully"
        else
            print_warning "Failed to update jetson-containers. Please try again manually."
            return 1
        fi
    else
        print_info "Cloning jetson-containers repository..."
        if git clone https://github.com/dusty-nv/jetson-containers.git "$jetson_containers_path" 2>&1 | sed "s/^/  /"; then
            print_success "jetson-containers repository cloned"
            if [ "$SUDO_USER" ]; then
                sudo chown -R "$SUDO_USER" "$jetson_containers_path"
            fi
        else
            print_error "Failed to clone jetson-containers repository"
            return 1
        fi
    fi

    # Check if jetson-containers and autotag are installed
    if ! command -v jetson-containers >/dev/null 2>&1 || ! command -v autotag >/dev/null 2>&1; then
        print_info "Installing jetson-containers tools..."
        if [ "$SUDO_USER" ]; then
            if sudo -u "$SUDO_USER" bash "$jetson_containers_path/install.sh"; then
                print_success "jetson-containers tools installed successfully"
            else
                print_error "Failed to install jetson-containers tools"
                return 1
            fi
        else
            if bash "$jetson_containers_path/install.sh"; then
                print_success "jetson-containers tools installed successfully"
            else
                print_error "Failed to install jetson-containers tools"
                return 1
            fi
        fi
    else
        print_success "jetson-containers tools already installed"
    fi
    JETSON_CONTAINERS_INSTALLED=true

    return 0
}

install_demo_apps() {
    print_info "Installing dependencies for demo applications...\n"
    printf "\n"

    # Install vLLM image for Jetson
    print_info "Pulling vLLM Docker image ($VLLM_IMAGE) for Jetson..."
    docker pull $VLLM_IMAGE 2>&1 | sed "s/^/  /"
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${VLLM_IMAGE}$"; then
        print_success "vLLM image downloaded successfully"
    else
        print_error "Failed to pull vLLM image"
        printf "  You can try again manually with:\n"
        printf "  ${CYAN}docker pull $VLLM_IMAGE${NC}\n"
        return 1
    fi

    # Download VLM model for demo
    print_info "Downloading VLM model for demo ($DEMO_VLM_MODEL)..."
    printf "  This may take several minutes depending on your internet connection...\n"

    local options="--rm --volume $(jetson-containers data):/data"
    if docker run $options $VLLM_IMAGE huggingface-cli download $DEMO_VLM_MODEL 2>&1 | sed "s/^/  /"; then
        print_success "$DEMO_VLM_MODEL downloaded successfully"
    else
        print_error "Failed to download VLM model for demo"
        printf "  You can try again manually with:\n"
        printf "  ${CYAN}docker run $options $VLLM_IMAGE huggingface-cli download $DEMO_VLM_MODEL${NC}\n"
        return 1
    fi

    # Download demo image
    print_info "Downloading AI Fusion Kit demo image..."
    docker pull $DEMO_IMAGE 2>&1 | sed "s/^/  /"
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${DEMO_IMAGE}$"; then
        print_success "AI Fusion Kit demo image downloaded successfully"
    else
        print_error "Failed to download AI Fusion Kit demo image"
        printf "  You can try again manually with:\n"
        printf "  ${CYAN}docker pull $DEMO_IMAGE${NC}\n"
        return 1
    fi

    DEMO_INSTALLED=true

    return 0
}

print_summary() {
    print_header "Setup Summary"

    if [ "$INTERNET_CONNECTED" = true ]; then
        printf "  ${GREEN}[O]${NC} Internet connectivity verified\n"
    else
        printf "  ${RED}[X]${NC} Internet connectivity verified\n"
    fi

    if [ "$SYSTEM_TIME_VALID" = true ]; then
        printf "  ${GREEN}[O]${NC} System time validated\n"
    else
        printf "  ${RED}[X]${NC} System time validated\n"
    fi

    if [ "$POWER_MODE_SET" = true ]; then
        printf "  ${GREEN}[O]${NC} Power mode configured\n"
    else
        printf "  ${RED}[X]${NC} Power mode configured\n"
    fi

    if [ "$AVERMEDIA_UDEV_RULES_SET" = true ]; then
        printf "  ${GREEN}[O]${NC} AVerMedia udev rules added\n"
    else
        printf "  ${RED}[X]${NC} AVerMedia udev rules added\n"
    fi

    if [ "$JETPACK_COMPONENTS_ALL_INSTALLED" = true ]; then
        printf "  ${GREEN}[O]${NC} Full NVIDIA JetPack components installed\n"
    elif [ "$JETPACK_COMPONENTS_NECESSARY_INSTALLED" = true ]; then
        printf "  ${GREEN}[O]${NC} ${YELLOW}Necessary${NC} NVIDIA JetPack components installed\n"
    else
        printf "  ${RED}[X]${NC} NVIDIA JetPack components installed\n"
    fi

    if [ "$DOCKER_INSTALLED" = true ]; then
        printf "  ${GREEN}[O]${NC} Docker installed and configured\n"
    else
        printf "  ${RED}[X]${NC} Docker installed and configured\n"
    fi

    if [ "$JETSON_CONTAINERS_INSTALLED" = true ]; then
        printf "  ${GREEN}[O]${NC} jetson-containers installed\n"
    else
        printf "  ${RED}[X]${NC} jetson-containers installed\n"
    fi

    if [ "$DEMO_INSTALLED" = true ]; then
        printf "  ${GREEN}[O]${NC} Demo applications installed\n"
    else
        printf "  ${RED}[X]${NC} Demo applications installed\n"
    fi
}

#===============================================================================
# Script Initialization
#===============================================================================

parse_arguments "$@"
init_terminal

print_banner

# Check if the script is running as root
if [ -z "$SUDO_USER" ]; then
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running script directly as root"
        printf "          It is recommended to login as a regular user and use sudo to run this script.\n"
        if ! ask_user "Continue anyway?"; then
            exit 1
        fi
    else
        print_error "This script requires sudo privileges."
        printf "        Please run the script with: ${CYAN}sudo ./setup.sh${NC}\n"
        exit 1
    fi
else
    printf "\n"
    print_info "Caching sudo credentials for user \"%s\"" "$SUDO_USER"
    printf "       You may need to enter your password again.\n"
    sudo -u "$SUDO_USER" sudo -v
    printf "\n"
fi

#===============================================================================
# Main Setup Process
#===============================================================================

# Step 1: Check prerequisites
print_step "Checking Prerequisites"
if ! check_internet; then
    exit 1
fi

if ! check_time; then
    exit 1
fi

# Step 2: System configuration
print_step "Configuring System Settings"

if ! detect_l4t_version; then
    exit 1
fi

print_info "Setting power mode to MAXN or MAXN SUPER..."
if sudo nvpmodel -m 0; then
    print_success "Power mode set to maximum performance"
    POWER_MODE_SET=true
else
    print_warning "Failed to set power mode"
    printf "  You can try manually: ${CYAN}sudo nvpmodel -m 0${NC}\n\n"
fi

# Show the current power mode
nvpmodel -q 2>&1 | sed "s/^/  /"
printf "\n"

if ! add_udev_rules; then
    exit 1
fi

# Step 3: Update system packages
print_step "Updating System Packages"
print_info "Updating package lists..."
sudo apt-get update 2>&1 | sed "s/^/  /"

print_info "Installing common dependencies..."
sudo apt-get install -y ca-certificates curl git jq 2>&1 | sed "s/^/  /"
print_success "Common dependencies installed"

# Step 4: Install NVIDIA JetPack components
print_step "Installing NVIDIA JetPack Components"
if ! install_jetpack; then
    exit 1
fi

# Step 5: Install Docker
print_step "Installing Docker"
if [ "$JETPACK_COMPONENTS_NECESSARY_INSTALLED" = true ]; then
    if ! install_docker; then
        print_error "Failed to install Docker"
    fi
else
    print_warning "NVIDIA JetPack components are not installed. Skipping Docker installation."
fi

# Step 6: Install jetson-containers
print_step "Installing jetson-containers tool"
if ! install_jetson_containers; then
    print_error "Failed to install jetson-containers"
fi

# Step 7: Optional demo applications
print_step "Demo Applications Setup"

if [ "$DOCKER_INSTALLED" = true ] && [ "$JETSON_CONTAINERS_INSTALLED" = true ]; then
    message=""
    message+="  ${BOLD}AVerMedia AI Fusion Kit Demo Applications${NC}\n"
    message+="\n"
    message+="  The following components will be installed:\n"
    message+="    ${BOLD}Docker images:${NC}\n"
    message+="      ${BULLET_SYMBOL} ${DEMO_IMAGE}\n"
    message+="      ${BULLET_SYMBOL} ${VLLM_IMAGE}\n"
    message+="\n"
    message+="    ${BOLD}Models:${NC}\n"
    message+="      ${BULLET_SYMBOL} ${DEMO_VLM_MODEL}\n"
    message+="\n"
    printf "$message"

    if ask_user "Would you like to install the demo applications now?" "y"; then
        if ! install_demo_apps; then
            exit 1
        fi
    fi
else
    print_warning "Docker or jetson-containers is not installed. Skipping demo applications installation."
fi

# Step 8: Final summary
print_step "Setup Complete"
print_summary

printf "\n"
print_header "Next Steps"
next_step_count=0

if [ "$DOCKER_INSTALLED" = true ] && [ "$USER_JUST_ADDED_TO_DOCKER_GROUP" = true ]; then
    next_step_count=$((next_step_count + 1))
    message=""
    message+="  ${BOLD}${next_step_count}. Docker Group Membership:${NC}\n"
    message+="\n"
    message+="     You may need to log out and back in to run Docker commands without sudo.\n"
    message+="     Alternatively, run:\n"
    message+="\n"
    message+="       ${CYAN}newgrp docker${NC}\n"
    message+="\n"
    printf "$message"
fi

if [ "$DEMO_INSTALLED" = true ]; then
    next_step_count=$((next_step_count + 1))
    message=""
    message+="  ${BOLD}${next_step_count}. Run Demo Applications:${NC}\n"
    message+="\n"
    message+="     ${CYAN}cd <avt-ai-fusion-kit>/demo${NC}\n"
    message+="     ${CYAN}docker compose up${NC}\n"
    message+="\n"
    printf "$message"

    if ! docker images | grep -q "riva-speech"; then
        next_step_count=$((next_step_count + 1))
        message=""
        message+="${BOLD}${next_step_count}. Optional - NVIDIA Riva for Speech Features:${NC}\n\n"
        message+="To enable voice interaction in demo applications, install NVIDIA Riva. "
        message+="Please refer to the AVerMedia AI Fusion Kit quick start guide or "
        message+="NVIDIA Riva documentation for details.\n\n"

        printf "$message" | fold -s -w "$TERMINAL_WIDTH" | sed "s/^/  /"
    fi
fi

if [ "$INTERNET_CONNECTED" = false ] || [ "$SYSTEM_TIME_VALID" = false ] || [ "$POWER_MODE_SET" = false ] || \
    [ "$AVERMEDIA_UDEV_RULES_SET" = false ] || [ "$JETPACK_COMPONENTS_NECESSARY_INSTALLED" = false ] || \
    [ "$DOCKER_INSTALLED" = false ] || [ "$JETSON_CONTAINERS_INSTALLED" = false ]; then
    print_error "Some necessary steps failed. Please check the log for more details."
    exit 1
fi

if [ "$next_step_count" -eq 0 ]; then
    printf "Enjoy exploring the AVerMedia AI Fusion Kit!\n"
fi

print_success "AVerMedia AI Fusion Kit development environment setup completed successfully!"

exit 0

