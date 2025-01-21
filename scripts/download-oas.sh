#!/bin/bash
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)

OAS_REPO_NAME=$1
OAS_REPO=$2
ALLOW_ALPHA=$3
OAS_API_VERSION=$4

if [[ -z ${OAS_REPO_NAME} ]]; then
    echo "Repo name is empty, default public OAS repo name will be used."
    OAS_REPO_NAME="stackit-api-specifications"
fi

if [[ ! ${OAS_REPO} || -d ${OAS_REPO} ]]; then
    echo "Repo argument is empty, default public OAS repo will be used."
    OAS_REPO="https://github.com/stackitcloud/${OAS_REPO_NAME}.git"
fi

if [[ -z ${OAS_API_VERSION} ]]; then
    echo "No API version passed, main branch will be used"
    OAS_API_VERSION="main"
fi

# Create temp directory to clone OAS repo
work_dir=$(mktemp -d)
if [[ ! ${work_dir} || -d {work_dir} ]]; then
    echo "! Unable to create temporary directory"
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
git clone ${OAS_REPO} --quiet

echo "Using api version ${OAS_API_VERSION}"
cd ${OAS_REPO_NAME}
git checkout --quiet ${OAS_API_VERSION}
cd -

for service_dir in ${work_dir}/${OAS_REPO_NAME}/services/*; do
    max_version_dir=""
    max_version=-1
    service=$(basename "$service_dir")

    # Prioritize GA over Beta over Alpha versions
    # GA priority = 3, Beta priority = 2, Alpha priority = 1
    max_version_priority=1

    for dir in ${service_dir}/*; do
        version=$(basename "$dir")
        current_version_priority=3
        # Check if directory name starts with 'v'
        if [[ ${version} == v* ]]; then
            # Remove the 'v' prefix
            version=${version#v}
            # Check if version is alpha
            if [[ ${version} == *alpha* ]]; then
                # To support initial integrations of the IaaS API in an Alpha state, we will temporarily use it to generate an IaaS Alpha SDK module
                # This check can be removed once the IaaS API moves all endpoints to Beta
                if [[ ${service} == "iaas" ]]; then
                    mv -f ${dir}/*.json ${ROOT_DIR}/oas/iaasalpha.json
                fi
                if [[ ${ALLOW_ALPHA} != "true" ]]; then
                    continue
                fi
                # Remove 'alpha' suffix
                version=${version%alpha*}
                current_version_priority=1
            fi
            # Check if version is beta
            if [[ ${version} == *beta* ]]; then
                # Remove 'beta' suffix
                version=${version%beta*}
                current_version_priority=2
            fi
            # Compare versions, prioritizing GA over Beta over Alpha versions
            if [[ $((version)) -gt ${max_version} || ($((version)) -eq ${max_version} && ${current_version_priority} -gt ${max_version_priority}) ]]; then
                max_version=$((version))
                max_version_dir=${dir}
                max_version_priority=${current_version_priority}
            fi
        fi
    done

    if [[ -z ${max_version_dir} ]]; then
        echo "No elegible OAS found for ${service_dir}"
        continue
    fi
    mv -f ${max_version_dir}/*.json ${ROOT_DIR}/oas
done
