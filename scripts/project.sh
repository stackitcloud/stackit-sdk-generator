#!/bin/bash

# This script is used to manage the project, only used for installing the required tools for now
# Usage: ./project.sh [action]
# * tools: Install required tools to run the project
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
SDK_SETTINGS_PATH="${ROOT_DIR}/generator"
SDK_PATH="${ROOT_DIR}/sdk"

action=$1

if [ "$action" = "help" ]; then
    [ -f "$0".man ] && man "$0".man || echo "No help, please read the script in ${script}, we will add help later"
elif [ "$action" = "tools" ]; then
    cd ${ROOT_DIR}

    go install golang.org/x/tools/cmd/goimports@latest
    pip install black==24.8.0 isort~=5.13.2 autoimport~=1.6.1
else
    echo "Invalid action: '$action', please use $0 help for help"
fi
