#!/usr/bin/env bash
# This script clones the SDK repo and updates it with the generated API modules
# Pre-requisites: Java
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
SDK_REPO_LOCAL_PATH="${ROOT_DIR}/sdk-repo-updated"

SERVICES_FOLDER="${SDK_REPO_LOCAL_PATH}/services"

GENERATOR_LOG_LEVEL="error" # Must be a Java log level (error, warn, info...)

INCLUDE_SERVICES=("alb" "iaas" "loadbalancer" "objectstorage" "resourcemanager" "serverbackup" "serverupdate" "sfs")

generate_java_sdk() {
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
        echo "! GIT_HOST not specified."
        exit 1
    fi

    if [[ -z ${GIT_USER_ID} ]]; then
        echo "! GIT_USER_ID id not specified."
        exit 1
    fi

    # Check optional parameters and set defaults if not provided
    if [[ -z ${GIT_REPO_ID} ]]; then
        echo "GIT_REPO_ID not specified, default will be used."
        GIT_REPO_ID="stackit-sdk-java"
    fi

    if [[ -z ${SDK_REPO_URL} ]]; then
        echo "SDK_REPO_URL not specified, default will be used."
        SDK_REPO_URL="https://github.com/stackitcloud/stackit-sdk-java.git"
    fi

    # Prepare folders
    if [[ ! -d $SERVICES_FOLDER ]]; then
        mkdir -p "$SERVICES_FOLDER"
    fi

    # Clone SDK repo
    if [ -d "${SDK_REPO_LOCAL_PATH}" ]; then
        echo "Old SDK repo clone was found, it will be removed."
        rm -rf "${SDK_REPO_LOCAL_PATH}"
    fi
    git clone --quiet -b "${SDK_BRANCH}" "${SDK_REPO_URL}" "${SDK_REPO_LOCAL_PATH}"

    # Backup of the current state of the SDK services dir (services/)
    sdk_services_backup_dir=$(mktemp -d)
    if [[ ! "${sdk_services_backup_dir}" || -d {sdk_services_backup_dir} ]]; then
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
    mkdir -p "${SERVICES_FOLDER}"

    warning=""
    
    # Generate SDK for each service
    for service_dir in "${ROOT_DIR}/oas/services"/*; do
        service="${service_dir##*/}"
        service="${service%.json}"

        service_pascal_case=$(to_pascal_case "${service}")

        # Remove invalid characters to ensure a valid Java pkg name
        service="${service//-/}"                                  # remove dashes
        service="${service// /}"                                  # remove spaces
        service=$(echo "${service}" | tr '[:upper:]' '[:lower:]') # convert upper case letters to lower case
        service=$(echo "${service}" | tr -d -c '[:alnum:]')       # remove non-alphanumeric characters

        # Ensure the package name doesn't start with a number
        if [[ "${service}" =~ ^[0-9] ]]; then
          service="_${service}" # Prepend a valid prefix if it starts with a number
        fi

        if ! [[ ${INCLUDE_SERVICES[*]} =~ ${service} ]]; then
            echo "Skipping not included service ${service}"
            warning+="Skipping not included service ${service}\n"
            continue
        fi

        # check if the whole service is blocklisted
        if grep -E "^$service$" "${ROOT_DIR}/languages/java/blocklist.txt"; then
            echo "Skipping blocklisted service ${service}"
            warning+="Skipping blocklisted service ${service}\n"
            continue
        fi
        
        echo -e "\n>> Generating SDK for \"${service}\" service..."
        for version_dir in "${service_dir}"/*; do
            service_version_json="${version_dir}/${service_dir##*/}.json"
            version="${version_dir##*/}"
            
            # check if that specific API version of the service is blocklisted
            if grep -E "^${service}-${version}$" "${ROOT_DIR}/languages/java/blocklist.txt"; then
                echo "Skipping blocklisted API version ${version} of service ${service}"
                warning+="Skipping blocklisted API version ${version} of service ${service}\n"
                continue
            fi

            echo -e "\n>> Generating SDK package \"${version}api\" for \"${service}\" service..."
            cd "${ROOT_DIR}"

            mkdir -p "${SERVICES_FOLDER}/${service}"
            cp "${ROOT_DIR}/languages/java/.openapi-generator-ignore" "${SERVICES_FOLDER}/${service}/.openapi-generator-ignore"

            SERVICE_DESCRIPTION=$(cat "${service_version_json}" | jq .info.title --raw-output)

            # Run the generator
            java -Dlog.level="${GENERATOR_LOG_LEVEL}" -jar "${GENERATOR_JAR_PATH}" generate \
                --generator-name java \
                --input-spec "${service_version_json}" \
                --output "${SERVICES_FOLDER}/${service}" \
                --git-host "${GIT_HOST}" \
                --git-user-id "${GIT_USER_ID}" \
                --git-repo-id "${GIT_REPO_ID}" \
                --global-property apis,models,modelTests=false,modelDocs=false,apiDocs=false,apiTests=true,supportingFiles \
                --additional-properties="artifactId=${service},artifactDescription=${SERVICE_DESCRIPTION},invokerPackage=cloud.stackit.sdk.${service}.${version}api,modelPackage=cloud.stackit.sdk.${service}.${version}api.model,apiPackage=cloud.stackit.sdk.${service}.${version}api.api,serviceName=${service_pascal_case}" \
                --inline-schema-options "SKIP_SCHEMA_REUSE=true" \
                --http-user-agent stackit-sdk-java/"${service}" \
                --config "${ROOT_DIR}/languages/java/openapi-generator-config.yml"

            # Rename DefaultApiServiceApi.java to {serviceName}Api.java
            # This approach is a workaround because the file name cannot be set dynamically via --additional-properties or the config file in OpenAPI Generator. 
            api_file="${SERVICES_FOLDER}/${service}/src/main/java/cloud/stackit/sdk/${service}/${version}api/api/DefaultApiServiceApi.java"
            if [ -f "$api_file" ]; then
                mv "$api_file" "${SERVICES_FOLDER}/${service}/src/main/java/cloud/stackit/sdk/${service}/${version}api/api/${service_pascal_case}Api.java"
            fi
            api_test_file="${SERVICES_FOLDER}/${service}/src/test/java/cloud/stackit/sdk/${service}/${version}api/api/DefaultApiTestServiceApiTest.java"
            if [ -f "$api_test_file" ]; then
                mv "$api_test_file" "${SERVICES_FOLDER}/${service}/src/test/java/cloud/stackit/sdk/${service}/${version}api/api/${service_pascal_case}ApiTest.java"
            fi
            
            build_gradle="${SERVICES_FOLDER}/${service}/${version}api/build.gradle"
            if [ -f "$build_gradle" ]; then
                mv "$build_gradle" "${SERVICES_FOLDER}/${service}/build.gradle"
            fi

            # Remove unnecessary files
            rm "${SERVICES_FOLDER}/${service}/.openapi-generator-ignore"
            rm -r "${SERVICES_FOLDER}/${service}/.openapi-generator/"

            # If the service version has a wait package, move them inside the service folder
            if [ -d "${sdk_services_backup_dir}/${service}/src/main/java/cloud/stackit/sdk/${service}/${version}api/wait" ]; then
                echo "Found ${service} \"wait\" package"
                cp -r "${sdk_services_backup_dir}/${service}/src/main/java/cloud/stackit/sdk/${service}/${version}api/wait" "${SERVICES_FOLDER}/${service}/${version}api/src/main/java/cloud/stackit/sdk/${service}/${version}api/wait"
            fi
            
            # If the service version has a wait test package, move them inside the service folder
            if [ -d "${sdk_services_backup_dir}/${service}/src/test/java/cloud/stackit/sdk/${service}/${version}api/wait" ]; then
                echo "Found ${service} \"wait\" test package"
                cp -r "${sdk_services_backup_dir}/${service}/src/test/java/cloud/stackit/sdk/${service}/${version}api/wait" "${SERVICES_FOLDER}/${service}/${version}api/src/test/java/cloud/stackit/sdk/${service}/${version}api/wait"
            fi
        done

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

        # If the service has oas_commit file, move it inside the service folder
        if [ -f "${sdk_services_backup_dir}/${service}/oas_commit" ]; then
            echo "Found ${service} \"oas_commit\" file"
            cp -r "${sdk_services_backup_dir}/${service}/oas_commit" "${SERVICES_FOLDER}/${service}/oas_commit"
        fi

    done

    cd "${SDK_REPO_LOCAL_PATH}"
    make fmt

    if [[ -n "$warning" ]]; then
        echo -e "\nSome of the services were skipped during creation!\n$warning"
    fi
}

to_pascal_case() {
    # Joins all arguments, splits on space or dash, capitalizes each part, and concatenates.
    echo "$1" | awk -F'[- ]' '{
        for (i=1; i<=NF; i++) {
            $i = toupper(substr($i,1,1)) tolower(substr($i,2))
        }
        printf "%s", $1
        for (i=2; i<=NF; i++) printf "%s", $i
        print ""
    }'
}
