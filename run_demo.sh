#!/bin/bash

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    printf "You are sourcing the script, which may pollute your environment. Please consider running it with:\n\n  bash %s\n\n" "${BASH_SOURCE[0]}"
    read -p "Continue anyway? [y/N] " response

    case $response in
        [Yy]|[Yy][Ee][Ss]) ;;
        *) printf "Exiting...\n"; return 1 ;;
    esac
fi

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            printf "Ignoring unknown option: %s\n" "$1"
            shift
            ;;
    esac
done

export UID

COMPOSE_FILE=compose.yaml
OVERRIDE_FILE=compose.override.yaml
ENV_FILE=.env

SCRIPT_DIR=$(dirname $(realpath $0))
OVERRIDE_FILEPATH="${SCRIPT_DIR}/${OVERRIDE_FILE}"
ENV_FILEPATH="${SCRIPT_DIR}/${ENV_FILE}"

detect_color_support() {
    if [ -t 1 ]; then
        if command -v tput >/dev/null 2>&1; then
            if [ "$(tput colors 2>/dev/null)" -ge 8 ]; then
                return 0
            fi
        fi
    fi

    return 1
}

printf_wrapped() {
    local format="$1"
    shift

    if command -v fold >/dev/null 2>&1; then
        printf "$format" "$@" | fold -w "$WIDTH"
    else
        printf "$format" "$@"
    fi
}

init_terminal() {
    WIDTH=$((${COLUMNS:-80} - 4))
    if [ "$WIDTH" -gt 120 ]; then
        WIDTH=120
    fi

    if [ -n "$NO_COLOR" ] || ! detect_color_support; then
        readonly RED=''
        readonly GREEN=''
        readonly YELLOW=''
        readonly BLUE=''
        readonly PURPLE=''
        readonly CYAN=''
        readonly WHITE=''
        readonly NC=''
    else
        readonly RED='\033[0;31m'
        readonly GREEN='\033[0;32m'
        readonly YELLOW='\033[1;33m'
        readonly BLUE='\033[0;34m'
        readonly PURPLE='\033[0;35m'
        readonly CYAN='\033[0;36m'
        readonly WHITE='\033[1;37m'
        readonly NC='\033[0m'
    fi
}

update_env_file() {
    local key=$1
    local value=$2

    if [ -f "$ENV_FILEPATH" ]; then
        if [ -n "$(grep "^#* *$key=" $ENV_FILEPATH)" ]; then
            sed -i "s|^#* *$key=.*|$key=$value|" $ENV_FILEPATH
        else
            echo "$key=$value" >> $ENV_FILEPATH
        fi
    else
        echo "$key=$value" > $ENV_FILEPATH
    fi
}

create_override_file() {
    if [ -f "$OVERRIDE_FILEPATH" ]; then
        printf "Recreating %s\n" "$OVERRIDE_FILE"
    else
        printf "Creating %s\n" "$OVERRIDE_FILE"
    fi

    printf "services:\n" > "$OVERRIDE_FILEPATH"
    printf "  app:\n" >> "$OVERRIDE_FILEPATH"

    # Find all the video devices and AVerMedia HID devices
    VIDEO_DEVICES=($(ls /dev/video*))
    SUPPORTED_HID_DEVICE_SYMLINKS=(
        "/dev/as311hid"
    )

    # Write the devices to the compose file
    printf "    devices:\n" >> "$OVERRIDE_FILEPATH"
    for device in "${VIDEO_DEVICES[@]}"; do
        printf "      - %s\n" "$device" >> "$OVERRIDE_FILEPATH"
    done

    for symlink in "${SUPPORTED_HID_DEVICE_SYMLINKS[@]}"; do
        if [ -e "$symlink" ]; then
            printf "      - %s\n" "$symlink" >> "$OVERRIDE_FILEPATH"
            printf "      - %s\n" "$(readlink -f "$symlink")" >> "$OVERRIDE_FILEPATH"
        fi
    done
}

load_or_create_env_file() {
    if [ -f "$ENV_FILEPATH" ]; then
        printf "Loading environment variables from %s (%s)\n" "$ENV_FILE" "$ENV_FILEPATH"
        source $ENV_FILEPATH
    else
        printf "Creating %s in %s\n" "$ENV_FILE" "$SCRIPT_DIR"
        cat <<EOF > $ENV_FILEPATH
JETSON_CONTAINERS_DATA_PATH=
USE_RIVA=
RIVA_MODEL_PATH=
EOF
        source $ENV_FILEPATH
    fi
}

find_jetson_containers() {
    if [ -n "$JETSON_CONTAINERS_DATA_PATH" ]; then
        printf "Using jetson-containers data path from .env: ${YELLOW}%s${NC}\n" "$JETSON_CONTAINERS_DATA_PATH"
        printf "If you want to use a different path, please edit the .env file.\n"
        return 0
    fi

    printf "JETSON_CONTAINERS_DATA_PATH is not set in .env. Searching for default paths...\n"

    DEFAULT_JETSON_CONTAINERS_PATHS=(
        "/opt/jetson-containers"
        "$HOME/jetson-containers"
    )

    for path in "${DEFAULT_JETSON_CONTAINERS_PATHS[@]}"; do
        if [ -d "$path/data" ]; then
            printf "Found jetson-containers at ${YELLOW}%s${NC}. Using LLM/VLM models in ${YELLOW}%s${NC}.\n" "$path" "$path/data"
            update_env_file JETSON_CONTAINERS_DATA_PATH $path/data
            return 0
        fi
    done

    printf "Failed to find jetson-containers path.\n\n"
    while true; do
        printf "Please enter the path where you installed jetson-containers (q to quit)\n"
        read -e -p ">> " response
        if [ "$response" = "q" ]; then
            printf "Exiting...\n"
            exit 1
        fi

        jetson_containers_path=$(realpath $response)
        if [ -d "$jetson_containers_path/data" ]; then
            printf "Using LLM/VLM models in %s.\n" "${YELLOW}${jetson_containers_path}/data${NC}"
            update_env_file JETSON_CONTAINERS_DATA_PATH $jetson_containers_path/data
            return 0
        else
            printf "The path you entered is not a valid jetson-containers path. Please enter the correct path.\n\n"
        fi
    done
}

find_riva_model_directory() {
    if [ "$USE_RIVA" = false ]; then
        printf "Riva is disabled. To enable Riva, please set the USE_RIVA environment variable to true in the .env file.\n"
        return 0
    fi

    if [ -n "$RIVA_MODEL_PATH" ]; then
        printf "Using Riva model path from .env: ${YELLOW}%s${NC}\n" "$RIVA_MODEL_PATH"
        printf "If you want to use a different path, please edit the .env file.\n"
        update_env_file USE_RIVA true
        return 0
    fi

    printf "RIVA_MODEL_PATH is not set in .env. Searching for default paths...\n"

    DEFAULT_RIVA_MODEL_PATHS=(
        "$HOME/riva_quickstart_arm64_v2.19.0/model_repository"
        "/opt/riva_quickstart_arm64_v2.19.0/model_repository"
    )

    for path in "${DEFAULT_RIVA_MODEL_PATHS[@]}"; do
        if [ -d "$path" ] && [ -d "$path/models" ] && [ -d "$path/prebuilt" ]; then
            printf "Found valid Riva model directory at ${YELLOW}%s${NC}. Using Riva models in ${YELLOW}%s${NC}.\n" "$path" "$path"
            update_env_file USE_RIVA true
            update_env_file RIVA_MODEL_PATH $path
            return 0
        fi
    done

    printf "Failed to find Riva model directory. You can either provide the path to the Riva model directory manually or continue without Riva.\n"
    read -p "Do you want to continue without Riva? [Y/n] " response
    case $response in
        [Yy]|[Yy][Ee][Ss])
            update_env_file USE_RIVA false
            return 0
            ;;
        *) ;;
    esac

    printf '\nBy default, if you installed Riva with the quick start scripts, the Riva model directory is located at "riva_quickstart_arm64_v2.19.0/model_repository".\n'

    while true; do
        printf "Please enter the path to the Riva model directory (q to quit)\n"
        read -e -p ">> " response
        if [ "$response" = "q" ]; then
            printf "Exiting...\n"
            exit 1
        fi

        riva_model_path=$(realpath $response)
        if [ -d "$riva_model_path" ]; then
            if [ -d "$riva_model_path/models" ] && [ -d "$riva_model_path/prebuilt" ]; then
                printf "Using Riva models in ${YELLOW}%s${NC}.\n" "$riva_model_path"
                update_env_file USE_RIVA true
                update_env_file RIVA_MODEL_PATH $riva_model_path
                return 0
            else
                printf "The path you entered is not a valid Riva model path. Please enter the correct path.\n"
            fi
        else
            printf "The path you entered is not a directory. Please enter the correct path.\n"
        fi
    done
}

init_terminal

create_override_file
load_or_create_env_file
printf "\n"

find_jetson_containers
printf "\n"

find_riva_model_directory
printf "\n"

source $ENV_FILEPATH

printf "%0.s—" $(seq 1 ${COLUMNS:-80})
printf "\n\n"


# Run the services
printf "The demo app and the services will be started by Docker Compose. "\
"Typically, it takes several minutes for the LLM server to finish the initialization. "\
"You can check the logs of the LLM server by running the following commands in another terminal:\n\n"
printf "  ${CYAN}docker compose --project-directory %s logs llm-server${NC}\n\n" "$SCRIPT_DIR"
printf "Note that even you close the GUI app, the services will continue to run in "\
"the background, so you would not need to wait for the long initialization again. "\
"To make sure all the services are stopped, you can either:\n\n"
printf "  1. Run the \"stop_demo.sh\" script.\n"
printf "  2. Run \"docker compose down\" in the this directory (%s).\n\n" "$SCRIPT_DIR"

if [ "$DRY_RUN" = false ]; then
    docker compose --project-directory $SCRIPT_DIR -f $COMPOSE_FILE -f $OVERRIDE_FILE up --wait -d app
else
    printf "Dry run. Skipping the actual Docker Compose command.\n"
fi
