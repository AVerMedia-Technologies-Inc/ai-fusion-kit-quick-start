#!/bin/bash

export UID

COMPOSE_FILE=compose.yaml
OVERRIDE_FILE=compose.override.yaml
SCRIPT_DIR=$(dirname $(realpath $0))

docker compose --project-directory $SCRIPT_DIR -f $COMPOSE_FILE -f $OVERRIDE_FILE down
