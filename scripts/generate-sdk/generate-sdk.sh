#!/bin/bash
# This script generates the SDK API modules
# Pre-requisites: Java, goimports, Go
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
GENERATOR_VERSION="6.5.0"
GENERATOR_SHASUM_512="b6f833fac749f1793e82dda86da261beb9236f644d1283904af569cb73825c83ad3b7ffd122fbbc1e27a830a33309290c0430d42c3d78f3d91a1bbe7eabad3fb"
GENERATOR_PATH="${ROOT_DIR}/scripts/bin"
GENERATOR_LOG_LEVEL="error" # Must be a Java log level (error, warn, info...)
PREPARE_SDK_PATH="${ROOT_DIR}/prepare-sdk"
SDK_PATH="${ROOT_DIR}/sdk"
SERVICES_BACKUP_PATH="${ROOT_DIR}/services"
SDK_REPO="https://github.com/stackitcloud/stackit-sdk-go.git"
SDK_GO_VERSION="1.18"

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
if [ -e ${jar_path} ] && [ $(java -jar ${jar_path} version) == ${GENERATOR_VERSION} ] && [ $(shasum -a 512 ${jar_path} | awk '{print $1;}') == ${GENERATOR_SHASUM_512} ]; then
    :
else
    echo "Downloading OpenAPI generator (version ${GENERATOR_VERSION}) to ${GENERATOR_PATH}..."
    mkdir -p ${GENERATOR_PATH}
    wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/${GENERATOR_VERSION}/openapi-generator-cli-${GENERATOR_VERSION}.jar -O ${jar_path}
    echo "Download done."
    if [ $(shasum -a 512 ${jar_path} | awk '{print $1;}') != ${GENERATOR_SHASUM_512} ]; then
        echo "Checksum of downloaded .jar is wrong, download corrupted."
        exit 1
    fi
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
    service="${service//-/}"
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
