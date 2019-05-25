#!/bin/bash

MAIN_DIR=$(eval 'echo ~/minecraft')
MINECRAFT_DIR=$(eval 'echo ~/minecraft_directory')
TARGET="${MINECRAFT_DIR}/$1"

if [ "" = "$1" ]; then
    echo "please set target dir"
    exit 1
fi

if [ ! -d "${TARGET}" ]; then
    echo "'${TARGET}' is not exist"
    exit 1
fi

bash "${MAIN_DIR}/mc_script.sh" stop
unlink "${MAIN_DIR}"
ln -s "${TARGET}" "${MAIN_DIR}"
bash "${MAIN_DIR}/mc_script.sh" start
exit 0
