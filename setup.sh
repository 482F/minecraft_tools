#!/bin/bash

MAIN_DIR=$(eval 'echo ~/minecraft')
MINECRAFT_DIR=$(eval 'echo ~/minecraft_directory')
SCRIPT_DIR=$(cd $(dirname $0); pwd)

CHANGE_TARGET_SH="change_target.sh"

if [ ! -d "${MINECRAFT_DIR}" ]; then
    mkdir "${MINECRAFT_DIR}"
fi

if [ ! -f "${MINECRAFT_DIR}/${CHANGE_TARGET_SH}" ]; then
    ln -s "${SCRIPT_DIR}/${CHANGE_TARGET_SH}" "${MINECRAFT_DIR}/${CHANGE_TARGET_SH}"
fi
