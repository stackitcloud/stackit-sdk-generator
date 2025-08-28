#!/bin/bash

# This script is used to manage the project, only used for installing the required tools for now
# Usage: ./project.sh [action]
# * tools: Install required tools to run the project
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
SDK_SETTINGS_PATH="${ROOT_DIR}/generator"
SDK_PATH="${ROOT_DIR}/sdk"

action=$1

if [[ -z $2 ]]; then
    echo "LANGUAGE not specified, default will be used."
    LANGUAGE="go"
else
    LANGUAGE=$2
fi

if [ "$action" = "help" ]; then
    [ -f "$0".man ] && man "$0".man || echo "No help, please read the script in ${script}, we will add help later"
elif [ "$action" = "tools" ]; then
    cd ${ROOT_DIR}
    if [ "${LANGUAGE}" == "go" ]; then
        go install golang.org/x/tools/cmd/goimports@latest
    elif [ "${LANGUAGE}" == "python" ]; then
        pip install black==24.8.0 isort~=5.13.2 autoimport~=1.6.1
    elif [ "${LANGUAGE}" == "java" ]; then
        echo "No additional project setup for java needed"
    else
        echo "! Invalid language: $($LANGUAGE), please use $0 help for help"
    fi
else
    echo "! Invalid action: '$action', please use $0 help for help"
fi
