#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)

OAS_REPO_NAME=$1
OAS_REPO=$2
ALLOW_ALPHA=$3
OAS_API_VERSIONS=$4

if [[ -z ${OAS_REPO_NAME} ]]; then
	echo "Repo name is empty, default public OAS repo name will be used."
	OAS_REPO_NAME="stackit-api-specifications"
fi

if [[ ! ${OAS_REPO} || -d ${OAS_REPO} ]]; then
	echo "Repo argument is empty, default public OAS repo will be used."
	OAS_REPO="https://github.com/stackitcloud/${OAS_REPO_NAME}.git"
fi

if [[ -z ${OAS_API_VERSIONS} ]]; then
	echo "No API version passed, using ${ROOT_DIR}/api-versions-lock.json"
	OAS_API_VERSIONS="${ROOT_DIR}/api-versions-lock.json"
fi

# Create temp directory to clone OAS repo
work_dir=$(mktemp -d)
if [[ ! ${work_dir} || -d {work_dir} ]]; then
	echo "! Unable to create temporary directory"
	exit 1
fi
trap "rm -rf ${work_dir}" EXIT # Delete temp directory on exit

if [ -d "${ROOT_DIR}/oas" ]; then
	echo "OAS folder found. Will be removed"
	rm -r "${ROOT_DIR}/oas"
fi

# Move oas to root level
mkdir "${ROOT_DIR}/oas"
cd "${work_dir}"
git clone "${OAS_REPO}" --quiet

for service_dir in ${work_dir}/${OAS_REPO_NAME}/services/*; do

	max_version_dir=""
	max_version=-1
	service=$(basename "$service_dir")

	apiVersion=$(jq -r -f <(
		cat <<EOF
if has("${service}") then ."${service}" else "main" end
EOF
	) ${OAS_API_VERSIONS})
	if [ "${apiVersion}" != "main" ]; then
		echo "Using ${apiVersion} for ${service}"
	fi
	cd ${work_dir}/${OAS_REPO_NAME} >/dev/null
	git checkout -q $apiVersion || (echo "version ${apiVersion} does not exist, using main instead" && git checkout -q main)

	# write commit hash to oas_commits file, normalize name first to match service name in sdk-create-pr.sh, normalization
	# occurs in go/java/python.sh when creating the SDK modules
	service_normalized=${service}
	service_normalized="${service_normalized//-/}"                                  # remove dashes
	service_normalized="${service_normalized// /}"                                  # remove empty spaces
	service_normalized="${service_normalized//_/}"                                  # remove underscores
	service_normalized=$(echo "${service_normalized}" | tr '[:upper:]' '[:lower:]') # convert upper case letters to lower case
	service_normalized=$(echo "${service_normalized}" | tr -d -c '[:alnum:]')       # remove non-alphanumeric characters
	echo "$service_normalized=$(git rev-parse HEAD)" >> oas_commits
	# To support initial integrations of the IaaS API in an Alpha state, we will temporarily use it to generate an IaaS Alpha SDK module
	# This check can be removed once the IaaS API moves all endpoints to Beta
	if [[ ${service_normalized} == "iaas" ]]; then
		echo "iaasalpha=$(git rev-parse HEAD)" >> oas_commits
	fi

	cd - >/dev/null

	# Prioritize GA over Beta over Alpha versions
	# GA priority =999, Beta priority >=500, Alpha priority <500 and >=1
	max_version_priority=1

	for dir in ${service_dir}/*; do
		version=$(basename "$dir")
		current_version_priority=999
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
					continue
				fi
				if [[ ${ALLOW_ALPHA} != "true" ]]; then
					continue
				fi

				current_version_priority=1

				# check if the version is e.g. "v2alpha2"
				if [[ ${version} =~ alpha([0-9]+)$ ]]; then
					alphaVersion="${BASH_REMATCH[1]}"
					current_version_priority=$((alphaVersion + current_version_priority))
				fi

				# Remove 'alpha' suffix
				version=${version%alpha*}
			fi
			# Check if version is beta
			if [[ ${version} == *beta* ]]; then
				current_version_priority=500

				# check if the version is e.g. "v2beta2"
				if [[ ${version} =~ beta([0-9]+)$ ]]; then
					betaVersion="${BASH_REMATCH[1]}"
					current_version_priority=$((betaVersion + current_version_priority))
				fi

				# Remove 'beta' suffix
				version=${version%beta*}
			fi
			# Compare versions, prioritizing GA over Beta over Alpha versions
			if [[ ($((version)) -ge ${max_version} && ${current_version_priority} -ge ${max_version_priority}) ]]; then
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
mv -f ${work_dir}/${OAS_REPO_NAME}/oas_commits ${ROOT_DIR}/oas/oas_commits