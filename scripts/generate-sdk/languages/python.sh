#!/bin/bash
# This script clones the SDK repo and updates it with the generated API modules
# Pre-requisites: Java, goimports, Go
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
SDK_REPO_LOCAL_PATH="${ROOT_DIR}/sdk-repo-updated"

OAS_REPO=https://github.com/stackitcloud/stackit-api-specifications

SERVICES_FOLDER="${SDK_REPO_LOCAL_PATH}/services"

GENERATOR_LOG_LEVEL="error" # Must be a Java log level (error, warn, info...)

generate_python_sdk() {
    # Required parameters
    local GENERATOR_JAR_PATH=$1
    local GIT_HOST=$2
    local GIT_USER_ID=$3

    # Optional parameters
    local GIT_REPO_ID=$4
    local SDK_REPO_URL=$5

    # Check required parameters
    if [[ -z ${GIT_HOST} ]]; then
        echo "GIT_HOST not specified."
        exit 1
    fi

    if [[ -z ${GIT_USER_ID} ]]; then
        echo "GIT_USER_ID id not specified."
        exit 1
    fi

    # Check optional parameters and set defaults if not provided
    if [[ -z ${GIT_REPO_ID} ]]; then
        echo "GIT_REPO_ID not specified, default will be used."
        GIT_REPO_ID="stackit-sdk-python"
    fi

    if [[ -z ${SDK_REPO_URL} ]]; then
        echo "SDK_REPO_URL not specified, default will be used."
        SDK_REPO_URL="https://github.com/stackitcloud/stackit-sdk-python.git"
    fi

    # Prepare folders
    if [[ ! -d $SERVICES_FOLDER ]]; then
      mkdir -p "$SERVICES_FOLDER"
    fi

    # Clone SDK repo
    if [ -d ${SDK_REPO_LOCAL_PATH} ]; then
        echo "Old SDK repo clone was found, it will be removed."
        rm -rf ${SDK_REPO_LOCAL_PATH}
    fi
    git clone --quiet ${SDK_REPO_URL} ${SDK_REPO_LOCAL_PATH}

    # Install SDK project tools
    cd ${ROOT_DIR}
    make project-tools

    # Backup of the current state of the SDK services dir (services/)
    sdk_services_backup_dir=$(mktemp -d)
    if [[ ! ${sdk_services_backup_dir} || -d {sdk_services_backup_dir} ]]; then
        echo "Unable to create temporary directory"
        exit 1
    fi
    cleanup() {
        rm -rf ${sdk_services_backup_dir}
    }
    cp -a "${SERVICES_FOLDER}/." ${sdk_services_backup_dir}

    # Cleanup after we are done
    trap cleanup EXIT

    # Remove old contents of services dir (services/)
    rm -rf ${SERVICES_FOLDER}    

    # Generate SDK for each service
    for service_json in ${ROOT_DIR}/oas/*.json; do
        service="${service_json##*/}"
        service="${service%.json}"

        # Remove invalid characters to ensure a valid Go pkg name
        service="${service//-/}"                                  # remove dashes
        service="${service// /}"                                  # remove empty spaces
        service="${service//_/}"                                  # remove underscores
        service=$(echo "${service}" | tr '[:upper:]' '[:lower:]') # convert upper case letters to lower case
        service=$(echo "${service}" | tr -d -c '[:alnum:]')       # remove non-alphanumeric characters

        echo "Generating \"${service}\" service..."
        cd ${ROOT_DIR}

        mkdir -p "${SERVICES_FOLDER}/${service}/"
        cp "${ROOT_DIR}/scripts/generate-sdk/.openapi-generator-ignore" "${SERVICES_FOLDER}/${service}/"

        # Run the generator
        java -Dlog.level=${GENERATOR_LOG_LEVEL} -jar ${jar_path} generate \
            --generator-name python \
            --input-spec "${service_json}" \
            --output "${SERVICES_FOLDER}/${service}" \
            --package-name "stackit.${service}" \
            --template-dir "${ROOT_DIR}/templates/python/" \
            --git-host ${GIT_HOST} \
            --git-user-id ${GIT_USER_ID} \
            --git-repo-id ${GIT_REPO_ID} \
            --global-property apis,models,modelTests=false,modelDocs=false,apiDocs=false,apiTests=false,supportingFiles \
            --additional-properties=pythonPackageName="stackit-${service},removeEnumValuePrefix=false" >/dev/null
        ##--enable-post-process-file \

        # Remove unnecessary files
        rm "${SERVICES_FOLDER}/${service}/.openapi-generator-ignore"
        rm -r "${SERVICES_FOLDER}/${service}/.openapi-generator/"
        rm "${SERVICES_FOLDER}/${service}/stackit/__init__.py"
        rm "${SERVICES_FOLDER}/${service}/.github/workflows/python.yml"
        
        
        # If the service has a wait package files, move them inside the service folder
        if [ -d ${sdk_services_backup_dir}/${service}/wait ]; then
            echo "Found ${service} \"wait\" package"
            cp -r ${sdk_services_backup_dir}/${service}/wait ${SERVICES_FOLDER}/${service}/wait
        fi

        # If the service has a CHANGELOG file, move it inside the service folder
        if [ -f ${sdk_services_backup_dir}/${service}/CHANGELOG.md ]; then
            echo "Found ${service} \"CHANGELOG\" file"
            cp -r ${sdk_services_backup_dir}/${service}/CHANGELOG.md ${SERVICES_FOLDER}/${service}/CHANGELOG.md
        fi

        # If the service has a LICENSE file, move it inside the service folder
        if [ -f ${sdk_services_backup_dir}/${service}/LICENSE.md ]; then
            echo "Found ${service} \"LICENSE\" file"
            cp -r ${sdk_services_backup_dir}/${service}/LICENSE.md ${SERVICES_FOLDER}/${service}/LICENSE.md
        fi

        # If the service has a NOTICE file, move it inside the service folder
        if [ -f ${sdk_services_backup_dir}/${service}/NOTICE.txt ]; then
            echo "Found ${service} \"NOTICE\" file"
            cp -r ${sdk_services_backup_dir}/${service}/NOTICE.txt ${SERVICES_FOLDER}/${service}/NOTICE.txt
        fi

        cd ${SERVICES_FOLDER}/${service}
        # Run formatter
        isort .
        autoimport --ignore-init-modules .
        black .
        
    done
}