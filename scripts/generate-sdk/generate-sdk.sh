#!/bin/bash
# This script generates the SDK API modules
# Pre-requisites: Java, goimports, Go
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
GENERATOR_PATH="${ROOT_DIR}/scripts/bin"
GENERATOR_LOG_LEVEL="error" # Must be a Java log level (error, warn, info...)
PREPARE_SDK_PATH="${ROOT_DIR}/prepare-sdk"
SDK_PATH="${ROOT_DIR}/sdk"
SERVICES_BACKUP_PATH="${ROOT_DIR}/services"
SDK_REPO="https://github.com/stackitcloud/stackit-sdk-go.git"
SDK_GO_VERSION="1.18"
OAS_REPO=https://github.com/stackitcloud/stackit-api-specifications

# Renovate: datasource=github-tags depName=OpenAPITools/openapi-generator versioning=semver
GENERATOR_VERSION="6.5.0"

mkdir_if_not_exists() {
    local directory="$1"
    if [ ! -d "$directory" ]; then
        mkdir -p "$directory"
    fi
}

cleanup() {
    rm -rf ${SDK_PATH}/.git
    rm -rf ${SERVICES_BACKUP_PATH}
    go env -w GOPRIVATE=${goprivate_backup}
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
if [ -e ${jar_path} ] && [ $(java -jar ${jar_path} version) == ${GENERATOR_VERSION} ]; then
    :
else
    echo "Downloading OpenAPI generator (version ${GENERATOR_VERSION}) to ${GENERATOR_PATH}..."
    mkdir -p ${GENERATOR_PATH}
    wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/${GENERATOR_VERSION}/openapi-generator-cli-${GENERATOR_VERSION}.jar -O ${jar_path}
    echo "Download done."
fi

# Get latest version of SDK
if [ -d ${ROOT_DIR}/sdk ]; then
    echo "Old sdk was found, it will be removed"
    rm -rf ${ROOT_DIR}/sdk
    mkdir ${ROOT_DIR}/sdk
fi
git clone ${SDK_REPO} ${SDK_PATH}

# Install SDK project tools
cd ${SDK_PATH}
make project-tools

# Set GOPRIVATE to download the SDK Go module
goprivate_backup=$(go env GOPRIVATE)
go env -w GOPRIVATE="github.com/stackitcloud"

# Save and remove generated contents of the SDK
mkdir_if_not_exists ${SERVICES_BACKUP_PATH}
cp -a "${SDK_PATH}/services/." ${SERVICES_BACKUP_PATH}
rm -rf ${SDK_PATH}/services
rm ${SDK_PATH}/go.work
if [ -f "${SDK_PATH}/go.work.sum" ]; then
    rm ${SDK_PATH}/go.work.sum
fi

# Cleanup after we are done
trap cleanup EXIT

echo "go ${SDK_GO_VERSION}" >${SDK_PATH}/go.work
cd ${SDK_PATH}/core
go work use .
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
        mkdir -p ${SDK_PATH}/services/${service}/
    cp ${ROOT_DIR}/scripts/generate-sdk/.openapi-generator-ignore ${SDK_PATH}/services/${service}/
    java -Dlog.level=${GENERATOR_LOG_LEVEL} -jar ${jar_path} generate \
        --generator-name go \
        --input-spec ${service_json} \
        --output ${SDK_PATH}/services/${service} \
        --package-name ${service} \
        --template-dir ${ROOT_DIR}/templates/ \
        --enable-post-process-file \
        --git-user-id stackitcloud \
        --git-repo-id stackit-sdk-go \
        --global-property apis,models,modelTests=true,modelDocs=false,apiDocs=false,supportingFiles \
        --additional-properties=isGoSubmodule=true
    rm ${SDK_PATH}/services/${service}/.openapi-generator-ignore
    rm ${SDK_PATH}/services/${service}/.openapi-generator/FILES

    # Move tests to the service folder
    cp ${SDK_PATH}/services/${service}/test/* ${SDK_PATH}/services/${service}
    rm -r ${SDK_PATH}/services/${service}/test/

    # If the service has waiter files, move them inside the service folder
    if [ -f ${SERVICES_BACKUP_PATH}/${service}/wait.go ]; then
        echo "Found wait.go"
        cp ${SERVICES_BACKUP_PATH}/${service}/wait.go ${SDK_PATH}/services/${service}/wait.go
    fi
    if [ -f ${SERVICES_BACKUP_PATH}/${service}/wait_test.go ]; then
        echo "Found wait_test.go"
        cp ${SERVICES_BACKUP_PATH}/${service}/wait_test.go ${SDK_PATH}/services/${service}/wait_test.go
    fi

    cd ${SDK_PATH}/services/${service}
    go work use .
    go mod tidy
done

# Add examples to workspace
for example_dir in ${SDK_PATH}/examples/*; do
    cd ${example_dir}
    go work use .
done

# Cleanup after SDK generation
cd ${SDK_PATH}
goimports -w ${SDK_PATH}/services/
make lint
