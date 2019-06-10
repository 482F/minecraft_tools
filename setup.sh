#!/bin/bash

MINECRAFT_DIR=$(eval 'echo ~/minecraft')
SCRIPT_DIR=$(cd $(dirname $0); pwd)

if [ ! -d "${MINECRAFT_DIR}" ]; then
    mkdir "${MINECRAFT_DIR}"
fi

SERVERS_DIR="${MINECRAFT_DIR}/servers"

SERVERS="$(ls -1 "${SERVERS_DIR}")"

echo "${SERVERS}" | while read SERVER; do
    SERVER="${SERVERS_DIR}/${SERVER}"
    if [ ! -f "${SERVER}/mc_script.sh" ]; then
        ln -s "${SCRIPT_DIR}/mc_script.sh" "${SERVER}/mc_script.sh"
    fi
done
