#!/bin/bash
# This script clones the SDK repo and updates it with the generated API modules
# Pre-requisites: Java, goimports, Go
set -eo pipefail

# Parameters
GIT_HOST=$1
GIT_USER_ID=$2
GIT_REPO_ID=$3
SDK_REPO_URL=$4
LANGUAGE=$5
SDK_BRANCH=$6

# Global variables
ROOT_DIR=$(git rev-parse --show-toplevel)
GENERATOR_PATH="${ROOT_DIR}/scripts/bin"
LANGUAGE_GENERATORS_FOLDER_PATH="${ROOT_DIR}/scripts/generate-sdk/languages/"
# Renovate: datasource=github-tags depName=OpenAPITools/openapi-generator versioning=semver

# Check parameters and set defaults if not provided
if [[ -z ${GIT_HOST} ]]; then
    echo "GIT_HOST not specified, default will be used."
    GIT_HOST="github.com"
fi

if [[ -z ${GIT_USER_ID} ]]; then
    echo "GIT_USER_ID not specified, default will be used."
    GIT_USER_ID="stackitcloud"
fi

if [[ -z ${LANGUAGE} ]]; then
    echo "LANGUAGE not specified, default will be used."
    LANGUAGE="go"
fi

if [[ -z ${SDK_BRANCH}  ]]; then
    echo "SDK_BRANCH not specified, main branch will be used."
    SDK_BRANCH=main
fi

# Check dependencies
if type -p java >/dev/null; then
    :
else
    echo "Java not installed, unable to proceed."
    exit 1
fi

if [ ! -d ${ROOT_DIR}/oas ]; then
    echo "\"oas\" folder not found in root. Please add it manually or run \"make download-oas\"."
    exit 1
fi
# Choose generator version depending on the language
# Renovate: datasource=github-tags depName=OpenAPITools/openapi-generator versioning=semver
case "${LANGUAGE}" in
go)
    GENERATOR_VERSION="v6.6.0" # There are issues with GO SDK generation in version v7
    ;;
python)
# Renovate: datasource=github-tags depName=OpenAPITools/openapi-generator versioning=semver
    GENERATOR_VERSION="v7.13.0"
    ;;
*)
    echo "SDK language not supported."
    exit 1
    ;;
esac
GENERATOR_VERSION_NUMBER="${GENERATOR_VERSION:1}"

# Download OpenAPI generator if not already downloaded
jar_path="${GENERATOR_PATH}/openapi-generator-cli.jar"
if [ -e ${jar_path} ] && [ $(java -jar ${jar_path} version) == ${GENERATOR_VERSION_NUMBER} ]; then
    :
else
    echo "Downloading OpenAPI generator (version ${GENERATOR_VERSION})..."
    mkdir -p ${GENERATOR_PATH}
    wget https://repo1.maven.org/maven2/org/openapitools/openapi-generator-cli/${GENERATOR_VERSION_NUMBER}/openapi-generator-cli-${GENERATOR_VERSION_NUMBER}.jar -O ${jar_path} --quiet
    echo "Download done."
fi

# Generate SDK for the specified language
case "${LANGUAGE}" in
go)
    echo -e "\n>> Generating the Go SDK..."

    source ${LANGUAGE_GENERATORS_FOLDER_PATH}/${LANGUAGE}.sh
    # Usage: generate_go_sdk GENERATOR_PATH GIT_HOST GIT_USER_ID [GIT_REPO_ID] [SDK_REPO_URL]
    generate_go_sdk "${jar_path}" "${GIT_HOST}" "${GIT_USER_ID}" "${GIT_REPO_ID}" "${SDK_REPO_URL}" "${SDK_BRANCH}"
    ;;
python)
    echo -e "\n>> Generating the Python SDK..."

    source ${LANGUAGE_GENERATORS_FOLDER_PATH}/${LANGUAGE}.sh
    # Usage: generate_python_sdk GENERATOR_PATH GIT_HOST GIT_USER_ID [GIT_REPO_ID] [SDK_REPO_URL] [SDK_BRANCH]
    generate_python_sdk "${jar_path}" "${GIT_HOST}" "${GIT_USER_ID}" "${GIT_REPO_ID}" "${SDK_REPO_URL}" "${SDK_BRANCH}"
    ;;
*)
    echo "! SDK language not supported."
    exit 1
    ;;
esac
