#!/bin/bash
# This script clones the SDK repo and updates it with the generated API modules
# Pre-requisites: Java, goimports, Go
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
SDK_REPO_LOCAL_PATH="${ROOT_DIR}/sdk-repo-updated"

OAS_REPO=https://github.com/stackitcloud/stackit-api-specifications

SDK_GO_VERSION="1.21"

SERVICES_FOLDER="${SDK_REPO_LOCAL_PATH}/services"
EXAMPLES_FOLDER="${SDK_REPO_LOCAL_PATH}/examples"
SCRIPTS_FOLDER="${SDK_REPO_LOCAL_PATH}/scripts"

GENERATOR_LOG_LEVEL="error" # Must be a Java log level (error, warn, info...)

SDK_GO_VERSION="1.21"

generate_go_sdk() {
    # Required parameters
    local GENERATOR_JAR_PATH=$1
    local GIT_HOST=$2
    local GIT_USER_ID=$3

    # Optional parameters
    local GIT_REPO_ID=$4
    local SDK_REPO_URL=$5
    local SDK_BRANCH=$6

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
        GIT_REPO_ID="stackit-sdk-go"
    fi

    if [[ -z ${SDK_REPO_URL} ]]; then
        echo "SDK_REPO_URL not specified, default will be used."
        SDK_REPO_URL="https://github.com/stackitcloud/stackit-sdk-go.git"
    fi

    # Check dependencies
    if type -p goimports >/dev/null; then
        :
    else
        echo "Goimports not installed, unable to proceed. For getting the dependencies, run "
        echo "make project-tools"
        exit 1
    fi

    if type -p go >/dev/null; then
        :
    else
        echo "! Go not installed, unable to proceed."
        exit 1
    fi

    # Clone SDK repo
    if [ -d ${SDK_REPO_LOCAL_PATH} ]; then
        echo "Old SDK repo clone was found, it will be removed."
        rm -rf ${SDK_REPO_LOCAL_PATH}
    fi
    git clone --quiet ${SDK_REPO_URL} ${SDK_REPO_LOCAL_PATH}

    # Install SDK project tools
    cd ${SDK_REPO_LOCAL_PATH}
    git checkout ${SDK_BRANCH}
    make project-tools

    # Backup of the current state of the SDK services dir (services/)
    sdk_services_backup_dir=$(mktemp -d)
    if [[ ! ${sdk_services_backup_dir} || -d {sdk_services_backup_dir} ]]; then
        echo "! Unable to create temporary directory"
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
    rm ${SDK_REPO_LOCAL_PATH}/go.work
    if [ -f "${SDK_REPO_LOCAL_PATH}/go.work.sum" ]; then
        rm ${SDK_REPO_LOCAL_PATH}/go.work.sum
    fi

    echo "go ${SDK_GO_VERSION}" >${SDK_REPO_LOCAL_PATH}/go.work
    if [ -d ${SDK_REPO_LOCAL_PATH}/core ]; then
        cd ${SDK_REPO_LOCAL_PATH}/core
        go work use .
    fi

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

        go_pkg_name_format="^[a-z0-9]+$"
        if [[ ! ${service} =~ ${go_pkg_name_format} ]]; then # check that it is a single lower case word
            echo "Service ${service} has an invalid Go package name even after removing invalid characters. The generate-sdk.sh script might need to be updated to catch corner case, contact the repo maintainers."
            exit 1
        fi

        contains_empty_space_pattern=" |'"
        if [[ ${service_json} =~ ${contains_empty_space_pattern} ]]; then
            echo "OAS filename ${service_json} has empty spaces, the generation will fail. If the OAS was downloaded using the make download-oas command, it should be fixed in the api-specifications repo, please contact the repo maintainers at ${OAS_REPO}."
            exit 1
        fi

        if grep -E "^$service$" ${ROOT_DIR}/blacklist.txt; then
            echo "Skipping blacklisted service ${service}"
            continue
        fi

        echo -e "\n>> Generating \"${service}\" service..."
        cd ${ROOT_DIR}

        GO_POST_PROCESS_FILE="gofmt -w" \
            mkdir -p ${SERVICES_FOLDER}/${service}/
        cp ${ROOT_DIR}/scripts/generate-sdk/.openapi-generator-ignore-go ${SERVICES_FOLDER}/${service}/.openapi-generator-ignore
        regional_api=
        if grep -E "^$service$" ${ROOT_DIR}/regional-whitelist.txt; then
            echo "Generating new regional api"
            regional_api="regional_api"
        fi

        # Run the generator for Go
        java -Dlog.level=${GENERATOR_LOG_LEVEL} -jar ${jar_path} generate \
            --generator-name go \
            --input-spec ${service_json} \
            --output ${SERVICES_FOLDER}/${service} \
            --package-name ${service} \
            --enable-post-process-file \
            --git-host ${GIT_HOST} \
            --git-user-id ${GIT_USER_ID} \
            --git-repo-id ${GIT_REPO_ID} \
            --global-property apis,models,modelTests=true,modelDocs=false,apiDocs=false,supportingFiles \
            --additional-properties=isGoSubmodule=true,enumClassPrefix=true,generateInterfaces=true,$regional_api \
	        --http-user-agent stackit-sdk-go/${service} \
            --reserved-words-mappings type=types \
            --config openapi-generator-config-go.yml
            
        # Remove unnecessary files
        rm ${SERVICES_FOLDER}/${service}/.openapi-generator-ignore
        rm ${SERVICES_FOLDER}/${service}/.openapi-generator/FILES

        # If there's a comment at the start of go.mod, copy it
        go_mod_backup_path="${sdk_services_backup_dir}/${service}/go.mod"
        if [ -f ${go_mod_backup_path} ]; then
            go_mod_backup_first_line="$(head -n 1 ${go_mod_backup_path})"
            is_comment_pattern="^\/\/"
            if [[ ${go_mod_backup_first_line} =~ ${is_comment_pattern} ]]; then
                echo "Found comment at the top of ${service}/go.mod"
                go_mod_path="${SERVICES_FOLDER}/${service}/go.mod"
                echo -e "${go_mod_backup_first_line}\n$(cat ${go_mod_path})" >${go_mod_path}
            fi
        fi

        # Move tests to the service folder
        cp ${SERVICES_FOLDER}/${service}/test/* ${SERVICES_FOLDER}/${service}
        rm -r ${SERVICES_FOLDER}/${service}/test/

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

        # If the service has a VERSION file, move it inside the service folder
        if [ -f ${sdk_services_backup_dir}/${service}/VERSION ]; then
            echo "Found ${service} \"VERSION\" file"
            cp -r ${sdk_services_backup_dir}/${service}/VERSION ${SERVICES_FOLDER}/${service}/VERSION
        fi

        cd ${SERVICES_FOLDER}/${service}
        go work use .
        # Make sure that dependencies are uptodate
        go get -u ./...
        go mod tidy
    done

    # Add examples to workspace
    if [ -d ${EXAMPLES_FOLDER} ]; then
        for example_dir in ${EXAMPLES_FOLDER}/*; do
            cd ${example_dir}
            go work use .
        done
    fi

    # Add scripts to workspace
    if [ -d ${SCRIPTS_FOLDER} ]; then
        cd ${SCRIPTS_FOLDER}
        go work use .
    fi

    # Cleanup after SDK generation
    cd ${SDK_REPO_LOCAL_PATH}
    goimports -w ${SERVICES_FOLDER}/
    make sync-tidy
}
