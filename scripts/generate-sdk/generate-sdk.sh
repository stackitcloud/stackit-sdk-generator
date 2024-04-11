#!/bin/bash
# This script clones the SDK repo and updates it with the generated API modules
# Pre-requisites: Java, goimports, Go
set -eo pipefail

GIT_HOST=$1
GIT_USER_ID=$2
GIT_REPO_ID=$3
SDK_REPO_URL=$4

ROOT_DIR=$(git rev-parse --show-toplevel)
GENERATOR_PATH="${ROOT_DIR}/scripts/bin"
GENERATOR_LOG_LEVEL="error" # Must be a Java log level (error, warn, info...)
SDK_REPO_LOCAL_PATH="${ROOT_DIR}/sdk-repo-updated"
SDK_GO_VERSION="1.18"
OAS_REPO=https://github.com/stackitcloud/stackit-api-specifications
SCRIPTS_FOLDER="${SDK_REPO_LOCAL_PATH}/scripts"

# Renovate: datasource=github-tags depName=OpenAPITools/openapi-generator versioning=semver
GENERATOR_VERSION="v6.6.0"
GENERATOR_VERSION_NUMBER="${GENERATOR_VERSION:1}"

if [[ -z ${GIT_HOST} ]]; then
    echo "Git host is empty, default will be used."
    GIT_HOST="github.com"
fi

if [[ -z ${GIT_USER_ID} ]]; then
    echo "Git user id is empty, default will be used."
    GIT_USER_ID="stackitcloud"
fi

if [[ -z ${GIT_REPO_ID} ]]; then
    echo "Git repo id is empty, default will be used."
    GIT_REPO_ID="stackit-sdk-go"
fi

if [[ -z ${SDK_REPO_URL} ]]; then
    echo "SDK repo URL is empty, default will be used."
    SDK_REPO_URL="https://github.com/stackitcloud/stackit-sdk-go.git"
fi

# Backup of the current state of the SDK services/
sdk_services_backup_dir=$(mktemp -d)
if [[ ! ${sdk_services_backup_dir} || -d {sdk_services_backup_dir} ]]; then
    echo "Unable to create temporary directory"
    exit 1
fi

cleanup() {
    rm -rf ${sdk_services_backup_dir}
}

if type -p java >/dev/null; then
    :
else
    echo "Java not installed, unable to proceed."
    exit 1
fi

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
    echo "Go not installed, unable to proceed."
    exit 1
fi

if [ ! -d ${ROOT_DIR}/oas ]; then
    echo "oas folder not found in root. Please add it manually or run make download-oas"
    exit 1
fi

jar_path="${GENERATOR_PATH}/openapi-generator-cli.jar"
if [ -e ${jar_path} ] && [ $(java -jar ${jar_path} version) == ${GENERATOR_VERSION_NUMBER} ]; then
    :
else
    echo "Downloading OpenAPI generator (version ${GENERATOR_VERSION}) to ${GENERATOR_PATH}..."
    mkdir -p ${GENERATOR_PATH}
    wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/${GENERATOR_VERSION_NUMBER}/openapi-generator-cli-${GENERATOR_VERSION_NUMBER}.jar -O ${jar_path}
    echo "Download done."
fi

# Clone SDK repo
if [ -d ${SDK_REPO_LOCAL_PATH} ]; then
    echo "Old SDK repo clone was found, it will be removed"
    rm -rf ${SDK_REPO_LOCAL_PATH}
fi
git clone ${SDK_REPO_URL} ${SDK_REPO_LOCAL_PATH}

# Install SDK project tools
cd ${SDK_REPO_LOCAL_PATH}
make project-tools

# Save and remove SDK services/
cp -a "${SDK_REPO_LOCAL_PATH}/services/." ${sdk_services_backup_dir}
rm -rf ${SDK_REPO_LOCAL_PATH}/services
rm ${SDK_REPO_LOCAL_PATH}/go.work
if [ -f "${SDK_REPO_LOCAL_PATH}/go.work.sum" ]; then
    rm ${SDK_REPO_LOCAL_PATH}/go.work.sum
fi

# Cleanup after we are done
trap cleanup EXIT

echo "go ${SDK_GO_VERSION}" >${SDK_REPO_LOCAL_PATH}/go.work
if [ -d ${SDK_REPO_LOCAL_PATH}/core ]; then
    cd ${SDK_REPO_LOCAL_PATH}/core
    go work use .
fi
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

    echo "Generating ${service} service..."
    cd ${ROOT_DIR}

    GO_POST_PROCESS_FILE="gofmt -w" \
        mkdir -p ${SDK_REPO_LOCAL_PATH}/services/${service}/
    cp ${ROOT_DIR}/scripts/generate-sdk/.openapi-generator-ignore ${SDK_REPO_LOCAL_PATH}/services/${service}/
    java -Dlog.level=${GENERATOR_LOG_LEVEL} -jar ${jar_path} generate \
        --generator-name go \
        --input-spec ${service_json} \
        --output ${SDK_REPO_LOCAL_PATH}/services/${service} \
        --package-name ${service} \
        --template-dir ${ROOT_DIR}/templates/ \
        --enable-post-process-file \
        --git-host ${GIT_HOST} \
        --git-user-id ${GIT_USER_ID} \
        --git-repo-id ${GIT_REPO_ID} \
        --global-property apis,models,modelTests=true,modelDocs=false,apiDocs=false,supportingFiles \
        --additional-properties=isGoSubmodule=true
    rm ${SDK_REPO_LOCAL_PATH}/services/${service}/.openapi-generator-ignore
    rm ${SDK_REPO_LOCAL_PATH}/services/${service}/.openapi-generator/FILES

    # If there's a comment at the start of go.mod, copy it
    go_mod_backup_path="${sdk_services_backup_dir}/${service}/go.mod"
    if [ -f ${go_mod_backup_path} ]; then
        go_mod_backup_first_line="$(head -n 1 ${go_mod_backup_path})"
        is_comment_pattern="^\/\/"
        if [[ ${go_mod_backup_first_line} =~ ${is_comment_pattern} ]]; then
            echo "Found comment at the top of ${service}/go.mod"
            go_mod_path="${SDK_REPO_LOCAL_PATH}/services/${service}/go.mod"
            echo -e "${go_mod_backup_first_line}\n$(cat ${go_mod_path})" >${go_mod_path}
        fi
    fi

    # Move tests to the service folder
    cp ${SDK_REPO_LOCAL_PATH}/services/${service}/test/* ${SDK_REPO_LOCAL_PATH}/services/${service}
    rm -r ${SDK_REPO_LOCAL_PATH}/services/${service}/test/

    # If the service has a wait package files, move them inside the service folder
    if [ -d ${sdk_services_backup_dir}/${service}/wait ]; then
        echo "Found ${service}/wait package"
        cp -r ${sdk_services_backup_dir}/${service}/wait ${SDK_REPO_LOCAL_PATH}/services/${service}/wait
    fi

    # If the service has a CHANGELOG file, move it inside the service folder
    if [ -f ${sdk_services_backup_dir}/${service}/CHANGELOG.md ]; then
        echo "Found ${service} CHANGELOG file"
        cp -r ${sdk_services_backup_dir}/${service}/CHANGELOG.md ${SDK_REPO_LOCAL_PATH}/services/${service}/CHANGELOG.md
    fi

    # If the service has a LICENSE file, move it inside the service folder
    if [ -f ${sdk_services_backup_dir}/${service}/LICENSE.md ]; then
        echo "Found ${service} LICENSE file"
        cp -r ${sdk_services_backup_dir}/${service}/LICENSE.md ${SDK_REPO_LOCAL_PATH}/services/${service}/LICENSE.md
    fi

    # If the service has a NOTICE file, move it inside the service folder
    if [ -f ${sdk_services_backup_dir}/${service}/NOTICE.txt ]; then
        echo "Found ${service} NOTICE file"
        cp -r ${sdk_services_backup_dir}/${service}/NOTICE.txt ${SDK_REPO_LOCAL_PATH}/services/${service}/NOTICE.txt
    fi

    cd ${SDK_REPO_LOCAL_PATH}/services/${service}
    go work use .
    go mod tidy
done

# Add examples to workspace
if [ -d ${SDK_REPO_LOCAL_PATH}/examples ]; then
    for example_dir in ${SDK_REPO_LOCAL_PATH}/examples/*; do
        cd ${example_dir}
        go work use .
    done
fi

# Add scripts to workspace
cd ${SCRIPTS_FOLDER}
go work use .

# Cleanup after SDK generation
cd ${SDK_REPO_LOCAL_PATH}
goimports -w ${SDK_REPO_LOCAL_PATH}/services/
make sync-tidy
