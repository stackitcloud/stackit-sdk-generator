#!/usr/bin/env bash
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
    if [ -d "${SDK_REPO_LOCAL_PATH}" ]; then
        echo "Old SDK repo clone was found, it will be removed."
        rm -rf "${SDK_REPO_LOCAL_PATH}"
    fi
    git clone --quiet "${SDK_REPO_URL}" "${SDK_REPO_LOCAL_PATH}"

    # Install SDK project tools
    cd "${SDK_REPO_LOCAL_PATH}"
    git checkout "${SDK_BRANCH}"
    make project-tools

    # Backup of the current state of the SDK services dir (services/)
    sdk_services_backup_dir=$(mktemp -d)
    if [[ ! ${sdk_services_backup_dir} || -d {sdk_services_backup_dir} ]]; then
        echo "! Unable to create temporary directory"
        exit 1
    fi
    cleanup() {
        rm -rf "${sdk_services_backup_dir}"
    }
    cp -a "${SERVICES_FOLDER}/." "${sdk_services_backup_dir}"

    # Cleanup after we are done
    trap cleanup EXIT

    # Remove old contents of services dir (services/)
    rm -rf "${SERVICES_FOLDER}"
    rm "${SDK_REPO_LOCAL_PATH}/go.work"
    if [ -f "${SDK_REPO_LOCAL_PATH}/go.work.sum" ]; then
        rm "${SDK_REPO_LOCAL_PATH}/go.work.sum"
    fi

    echo "go ${SDK_GO_VERSION}" >${SDK_REPO_LOCAL_PATH}/go.work
    if [ -d ${SDK_REPO_LOCAL_PATH}/core ]; then
        cd "${SDK_REPO_LOCAL_PATH}/core"
        go work use .
    fi
   
    # see https://openapi-generator.tech/docs/file-post-processing/
    export GO_POST_PROCESS_FILE="gofmt -w"

    warning=""
    
    for service_dir in "${ROOT_DIR}/oas/services"/*; do
        service="${service_dir##*/}"
        service="${service%.json}"

        compat_layer_service_oas_name="${service}"

        # Remove invalid characters to ensure a valid Go pkg name
        service="${service//-/}"                                  # remove dashes
        service="${service// /}"                                  # remove empty spaces
        service="${service//_/}"                                  # remove underscores
        service=$(echo "${service}" | tr '[:upper:]' '[:lower:]') # convert upper case letters to lower case
        service=$(echo "${service}" | tr -d -c '[:alnum:]')       # remove non-alphanumeric characters

        go_pkg_name_format="^[a-z0-9]+$"
        echo "${service_dir}"
        if [[ ! ${service} =~ ${go_pkg_name_format} ]]; then # check that it is a single lower case word
            echo "Service ${service} has an invalid Go package name even after removing invalid characters. The generate-sdk.sh script might need to be updated to catch corner case, contact the repo maintainers."
            exit 1
        fi

        # check if the whole service is blacklisted
        if grep -E "^$service$" "${ROOT_DIR}/languages/golang/blacklist.txt"; then
            echo "Skipping blacklisted service ${service}"
            warning+="Skipping blacklisted service ${service}\n"
            continue
        fi
        
        
        echo -e "\n>> Generating SDK for \"${service}\" service..."
        for version_dir in "${service_dir}"/*; do
            service_version_json="${version_dir}/${service_dir##*/}.json"
            version="${version_dir##*/}"
            
            # check if that specific API version of the service is blacklisted
            if grep -E "^${service}-${version}$" "${ROOT_DIR}/languages/golang/blacklist.txt"; then
                echo "Skipping blacklisted API version ${version} of service ${service}"
                warning+="Skipping blacklisted API version ${version} of service ${service}\n"
                continue
            fi
            
            echo -e "\n>> Generating SDK package \"${version}api\" for \"${service}\" service..."
        
            mkdir -p "${SERVICES_FOLDER}/${service}/${version}api"
            cp "${ROOT_DIR}/languages/golang/.openapi-generator-ignore" "${SERVICES_FOLDER}/${service}/${version}api/.openapi-generator-ignore"
            
            # Run the generator for Go
            java -Dlog.level=${GENERATOR_LOG_LEVEL} -jar ${jar_path} generate \
                --generator-name go \
                --input-spec "${service_version_json}" \
                --output "${SERVICES_FOLDER}/${service}/${version}api" \
                --package-name "${version}api" \
                --enable-post-process-file \
                --template-dir "${ROOT_DIR}/languages/golang/templates/" \
                --git-host "${GIT_HOST}" \
                --git-user-id "${GIT_USER_ID}" \
                --git-repo-id "${GIT_REPO_ID}/services/${service}" \
                --global-property apis,models,modelTests=true,modelDocs=false,apiDocs=false,supportingFiles,apiTests=false\
                --http-user-agent "stackit-sdk-go/${service}" \
                --reserved-words-mappings type=types \
                --config "${ROOT_DIR}/languages/golang/openapi-generator-config.yml"
        
            # Remove unnecessary files
            rm "${SERVICES_FOLDER}/${service}/${version}api/.openapi-generator-ignore"
            rm -r "${SERVICES_FOLDER}/${service}/${version}api/.openapi-generator"
        
            # If the service version has a wait package files, move them inside the service folder
            if [ -d "${sdk_services_backup_dir}/${service}/${version}api/wait" ]; then
                echo "Found ${service} \"wait\" package"
                cp -r "${sdk_services_backup_dir}/${service}/${version}api/wait" "${SERVICES_FOLDER}/${service}/${version}api/wait"
            fi
        done
        
        if ! grep -E "^$service$" "${ROOT_DIR}/languages/golang/compat-layer/allow-list.txt"; then
            echo "Skipping service ${service}, compatibility layer is not activated for it"
            warning+="Skipping compatibility layer generation for service ${service}\n"

            cp "${ROOT_DIR}/LICENSE.md" "${SERVICES_FOLDER}/${service}/LICENSE.md"
            if [ ! -f "${SERVICES_FOLDER}/${service}/go.mod" ]; then
                printf "module github.com/stackitcloud/stackit-sdk-go/services/${service}\n\n" > "${SERVICES_FOLDER}/${service}/go.mod" 
                printf "go ${SDK_GO_VERSION}\n\n" >> "${SERVICES_FOLDER}/${service}/go.mod" 
                printf "require (\n\tgithub.com/stackitcloud/stackit-sdk-go/core v0.21.1\n)\n" >> "${SERVICES_FOLDER}/${service}/go.mod" 
            fi

            # generate package.go
            printf "package ${service}\n" > "${SERVICES_FOLDER}/${service}/package.go" 


            cd "${SERVICES_FOLDER}/${service}"
            go work use .
            # Make sure that dependencies are uptodate
            go get -u ./...
            go mod tidy

            continue
        fi
    
        # COMPAT LAYER - LEGACY !! - START
        
        # Download OpenAPI generator if not already downloaded
        compat_layer_jar_path="${ROOT_DIR}/scripts/bin/openapi-generator-cli-go-compat-layer.jar"
        if [ -e ${compat_layer_jar_path} ] && [ $(java -jar ${compat_layer_jar_path} version) == "6.6.0" ]; then
            :
        else
            echo "Downloading OpenAPI generator (version 6.6.0) for generating the compatibility layer..."
            mkdir -p "${ROOT_DIR}/scripts/bin"
            wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/6.6.0/openapi-generator-cli-6.6.0.jar -O ${compat_layer_jar_path} --quiet
            echo "Download done."
        fi

        echo -e "\n>> Generating compatibility layer for \"${service}\" service..."
        cd "${ROOT_DIR}"

        mkdir -p "${SERVICES_FOLDER}/${service}"
        cp "${ROOT_DIR}/languages/golang/compat-layer/.openapi-generator-ignore" "${SERVICES_FOLDER}/${service}/.openapi-generator-ignore"
        regional_api=
        if grep -E "^$service$" ${ROOT_DIR}/languages/golang/compat-layer/regional-whitelist.txt; then
            echo "Generating new regional api"
            regional_api="regional_api"
        fi
        
        # Run the compatibility-layer generator for Go
        java -Dlog.level=${GENERATOR_LOG_LEVEL} -jar ${compat_layer_jar_path} generate \
            --generator-name go \
            --input-spec "${ROOT_DIR}/oas/legacy/${compat_layer_service_oas_name}.json" \
            --output "${SERVICES_FOLDER}/${service}" \
            --package-name "${service}" \
            --enable-post-process-file \
            --git-host "${GIT_HOST}" \
            --git-user-id "${GIT_USER_ID}" \
            --git-repo-id "${GIT_REPO_ID}" \
            --global-property apis,models,modelTests=true,modelDocs=false,apiDocs=false,supportingFiles,apiTests=false \
            --additional-properties=isGoSubmodule=true,enumClassPrefix=true,generateInterfaces=true,$regional_api \
            --http-user-agent "stackit-sdk-go/${service}" \
            --reserved-words-mappings type=types \
            --config "${ROOT_DIR}/languages/golang/compat-layer/openapi-generator-config.yml"
            
        # Remove unnecessary files
        rm "${SERVICES_FOLDER}/${service}/.openapi-generator-ignore"
        rm "${SERVICES_FOLDER}/${service}/.openapi-generator/FILES"

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

        # If the service has a wait package files, move them inside the service folder
        if [ -d "${sdk_services_backup_dir}/${service}/wait" ]; then
            echo "Found ${service} \"wait\" package"
            cp -r "${sdk_services_backup_dir}/${service}/wait" "${SERVICES_FOLDER}/${service}/wait"
            # deprecate legacy wait package
            printf "// Deprecated: Move to the packages generated for each available API version instead\npackage wait\n\n" > "${SERVICES_FOLDER}/${service}/wait/deprecation.go"
        fi

        # If the service has a CHANGELOG file, move it inside the service folder
        if [ -f "${sdk_services_backup_dir}/${service}/CHANGELOG.md" ]; then
            echo "Found ${service} \"CHANGELOG\" file"
            cp -r "${sdk_services_backup_dir}/${service}/CHANGELOG.md" "${SERVICES_FOLDER}/${service}/CHANGELOG.md"
        fi

        # If the service has a LICENSE file, move it inside the service folder
        if [ -f "${sdk_services_backup_dir}/${service}/LICENSE.md" ]; then
            echo "Found ${service} \"LICENSE\" file"
            cp -r "${sdk_services_backup_dir}/${service}/LICENSE.md" "${SERVICES_FOLDER}/${service}/LICENSE.md"
        fi

        # If the service has a NOTICE file, move it inside the service folder
        if [ -f "${sdk_services_backup_dir}/${service}/NOTICE.txt" ]; then
            echo "Found ${service} \"NOTICE\" file"
            cp -r "${sdk_services_backup_dir}/${service}/NOTICE.txt" "${SERVICES_FOLDER}/${service}/NOTICE.txt"
        fi

        # If the service has a VERSION file, move it inside the service folder
        if [ -f "${sdk_services_backup_dir}/${service}/VERSION" ]; then
            echo "Found ${service} \"VERSION\" file"
            cp -r "${sdk_services_backup_dir}/${service}/VERSION" "${SERVICES_FOLDER}/${service}/VERSION"
        fi
        
        cd "${SERVICES_FOLDER}/${service}"
        go work use .
        # Make sure that dependencies are uptodate
        go get -u ./...
        go mod tidy
    
        # COMPAT LAYER - LEGACY !! - END

    done

    # Add examples to workspace
    if [ -d "${EXAMPLES_FOLDER}" ]; then
        for example_dir in ${EXAMPLES_FOLDER}/*; do
            cd "${example_dir}"
            go work use .
        done
    fi

    # Add scripts to workspace
    if [ -d "${SCRIPTS_FOLDER}" ]; then
        cd "${SCRIPTS_FOLDER}"
        go work use .
    fi

    # Cleanup after SDK generation
    cd "${SDK_REPO_LOCAL_PATH}"
    goimports -w "${SERVICES_FOLDER}/"
    make sync-tidy

    if [[ -n "$warning" ]]; then
        echo -e "\nSome of the services were skipped during creation!\n$warning"
    fi
}
