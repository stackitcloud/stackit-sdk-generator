ROOT_DIR              ?= $(shell git rev-parse --show-toplevel)
SCRIPTS_BASE          ?= $(ROOT_DIR)/scripts

# SETUP AND TOOL INITIALIZATION TASKS
project-help:
	@$(SCRIPTS_BASE)/project.sh help

project-tools:
	@$(SCRIPTS_BASE)/project.sh tools "$(LANGUAGE)"

# GENERATE
download-oas:
	@$(SCRIPTS_BASE)/download-oas.sh "$(OAS_REPO_NAME)" "$(OAS_REPO)" "$(ALLOW_ALPHA)"
generate-sdk:
	@$(SCRIPTS_BASE)/generate-sdk/generate-sdk.sh "$(GIT_HOST)" "$(GIT_USER_ID)" "$(GIT_REPO_ID)" "$(SDK_REPO_URL)" "$(LANGUAGE)"

