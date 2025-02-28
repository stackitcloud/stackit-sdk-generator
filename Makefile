ROOT_DIR              ?= $(shell git rev-parse --show-toplevel)
SCRIPTS_BASE          ?= $(ROOT_DIR)/scripts
API_VERSION           ?= $(shell cat api_version|grep -v '^\#'|head -n 1)
SDK_BRANCH            ?= main

# SETUP AND TOOL INITIALIZATION TASKS
project-help:
	@$(SCRIPTS_BASE)/project.sh help

project-tools:
	@$(SCRIPTS_BASE)/project.sh tools "$(LANGUAGE)"

# GENERATE
download-oas:
	@$(SCRIPTS_BASE)/download-oas.sh "$(OAS_REPO_NAME)" "$(OAS_REPO)" "$(ALLOW_ALPHA)" "$(API_VERSION)"

download-oas-alpha:
	@$(SCRIPTS_BASE)/download-oas.sh "stackit-api-specifications-internal" "git@ssh.dev.azure.com:v3/schwarzit/schwarzit.stackit-public/stackit-api-specifications-internal" "true" "$(API_VERSION)"

generate-sdk:
	@$(SCRIPTS_BASE)/generate-sdk/generate-sdk.sh "$(GIT_HOST)" "$(GIT_USER_ID)" "$(GIT_REPO_ID)" "$(SDK_REPO_URL)" "$(LANGUAGE)" "$(SDK_BRANCH)"

