#!/bin/bash

MINECRAFT_DIR=$(eval 'echo ~/minecraft')
SCRIPT_DIR=$(cd $(dirname $0); pwd)

if [ ! -d "${MINECRAFT_DIR}" ]; then
    mkdir "${MINECRAFT_DIR}"
fi
