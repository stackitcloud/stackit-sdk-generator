#!/bin/bash
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
OAS_REPO_NAME="stackit-api-specifications"
OAS_REPO="https://github.com/stackitcloud/${OAS_REPO_NAME}.git"

# Create temp directory to clone OAS repo
work_dir=$(mktemp -d)
if [[ ! ${work_dir} || -d {work_dir} ]]; then
    echo "Unable to create temporary directory"
    exit 1
fi
trap "rm -rf ${work_dir}" EXIT # Delete temp directory on exit

if [ -d ${ROOT_DIR}/oas ]; then
    echo "OAS folder found. Will be removed"
    rm -r ${ROOT_DIR}/oas
fi

# Move oas to root level
mkdir ${ROOT_DIR}/oas
cd ${work_dir}
git clone ${OAS_REPO}

for service_dir in ${work_dir}/${OAS_REPO_NAME}/services/*; do
    max_version_dir=""
    max_version=""
    max_version_is_beta=false

    for dir in ${service_dir}/*; do
        version=$(basename "$dir")
        current_version_is_beta=false
        # Check if directory name starts with 'v'
        if [[ ${version} == v* ]]; then
            # Remove the 'v' prefix
            version=${version#v}
            # Check if version is beta
            if [[ ${version} == *beta* ]]; then
                # Remove 'beta' suffix
                version=${version%beta*}
                current_version_is_beta=true
            fi
            # Compare versions and prioritize non-beta versions
            if [[ ${version} > ${max_version} || (${version} == ${max_version} && ${current_version_is_beta} == false) ]]; then
                max_version=${version}
                max_version_dir=${dir}
                max_version_is_beta=${current_version_is_beta}
            fi
        fi
    done

    mv -f ${max_version_dir}/*.json ${ROOT_DIR}/oas
done
