#!/bin/bash
# This script pushes the generated SDK to its repo and creates a PR
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)
COMMIT_NAME="SDK Generator Bot"
COMMIT_EMAIL="noreply@stackit.de"
SDK_REPO_LOCAL_PATH="${ROOT_DIR}/sdk-repo-updated" # Comes from generate-sdk.sh

BRANCH_PREFIX=$1
COMMIT_INFO=$2

if [ $# -lt 2 ]; then
    echo "! Not enough arguments supplied. Required: 'branch-prefix' 'commit-info'"
    exit 1
fi

if type -p go >/dev/null; then
    :
else
    echo "! Go not installed, unable to proceed."
    exit 1
fi

if [ ! -d "${SDK_REPO_LOCAL_PATH}" ]; then
    echo "! SDK to commit not found in root. Please run make generate-sdk"
    exit 1
fi

if [[ -z $3 ]]; then
    REPO_URL_SSH="git@github.com:stackitcloud/stackit-sdk-go.git"
else
    REPO_URL_SSH=$3
fi

if [[ -z $4 ]]; then
    echo "LANGUAGE not specified, default will be used."
    LANGUAGE="go"
else
    LANGUAGE=$4
fi

# Create temp directory to work on
work_dir="$ROOT_DIR/temp"
mkdir -p "${work_dir}"
if [[ ! ${work_dir} || -d {work_dir} ]]; then
    echo "Unable to create temporary directory"
    exit 1
fi

# Delete temp directory on exit
trap "rm -rf ${work_dir}" EXIT

mkdir "${work_dir}/git_repo"    # Where the git repo will be created
mkdir "${work_dir}/sdk_backup"  # Backup of the SDK to check for new modules
mkdir "${work_dir}/sdk_to_push" # Copy of SDK to push

# Prepare SDK to push
cp -a "${SDK_REPO_LOCAL_PATH}/." "${work_dir}/sdk_to_push"
rm -rf "${work_dir}/sdk_to_push/.git"

# Initialize git repo
cd "${work_dir}/git_repo"
git clone "${REPO_URL_SSH}" ./ --quiet
git config user.name "${COMMIT_NAME}"
git config user.email "${COMMIT_EMAIL}"

cp -a . "${work_dir}/sdk_backup"

# Create PR for each new SDK module if there are changes
for service_path in ${work_dir}/sdk_to_push/services/*; do
    service="${service_path##*/}"

    # Replace old SDK with new one
    # Removal of pulled data is necessary because the old version may have files
    # that were deleted in the new version
    rm -rf "./services/${service}/*"
    cp -a "${work_dir}/sdk_to_push/services/${service}/." "./services/${service}"

    # Check for changes in the specific folder compared to main
    service_changes=$(git status --porcelain "services/$service")

    if [[ -n "$service_changes" ]]; then
        echo -e "\n>> Detected changes in $service service"

        if [[ "$BRANCH_PREFIX" != "main" ]]; then
            git switch main # This is needed to create a new branch for the service without including the previously committed files
            branch="$BRANCH_PREFIX/$service"
            git switch -c "$branch"
        else
            branch=$BRANCH_PREFIX
        fi

        if [ "${LANGUAGE}" == "go" ] && [ ! -d "${work_dir}/sdk_backup/services/${service}/" ]; then # Check if it is a newly added SDK module
            # go work use -r adds a use directive to the go.work file for dir, if it exists, and removes the use directory if the argument directory doesn’t exist
            # the -r flag examines subdirectories of dir recursively
            # this prevents errors if there is more than one new module in the SDK generation
            go work use -r .
        fi

        # If lint or test fails for a service, we skip it and continue to the next one
        make lint skip-non-generated-files=true service="$service" || {
            echo "! Linting failed for $service. THE UPDATE OF THIS SERVICE WILL BE SKIPPED."
            continue
        }
        # Our unit test template fails because it doesn't support fields with validations,
        # such as the UUID component used by IaaS. We introduce this hardcoded skip until we fix it
        if [ "${service}" = "iaas" ] || [ "${service}" = "iaasalpha" ]; then
            echo ">> Skipping tests of $service service"
        else
            make test skip-non-generated-files=true service="$service" || {
                echo "! Testing failed for $service. THE UPDATE OF THIS SERVICE WILL BE SKIPPED."
                continue
            }
        fi
        
        git add "services/${service}/"
        if [ "${LANGUAGE}" == "go" ] && [ ! -d "${work_dir}/sdk_backup/services/${service}/" ]; then # Check if it is a newly added SDK module
            git add go.work
        fi

        if [[ "$branch" != "main" ]]; then
            echo ">> Creating PR for $service"
            git commit -m "Generate $service"
            git push origin "$branch"
            gh pr create --title "Generator: Update SDK /services/$service" --body "$COMMIT_INFO" --head "$branch" --base "main"
        else
            echo ">> Pushing changes for $service service..."
            git commit -m "Generate $service: $COMMIT_INFO"
            git push origin "$branch"
        fi
    fi
done
