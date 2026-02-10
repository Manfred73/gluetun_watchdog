#!/bin/bash


# Load environment variables
source /share/homes/<user>/scripts/gluetun_watchdog/gluetun_watchdog.env

CURRENT_DIR="$PWD"
GLUETUN_CONTAINERS=()

while IFS= read -r line; do
   GLUETUN_CONTAINERS+=("$line")
done <$GLUETUN_CONTAINER_FILE

cd $DOCKER_DIR

for gluetun_container in "${GLUETUN_CONTAINERS[@]}"
do
    cd $gluetun_container
    . $DOCKER_COMPOSE_SCRIPT
    cd ..
done

cd $CURRENT_DIR
