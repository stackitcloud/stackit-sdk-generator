# Contribute to the STACKIT Go SDK
Your contribution is welcome! Thank you for your interest in contributing to the STACKIT SDK Generator. We greatly value your feedback, feature requests, additions to the code, bug reports or documentation extensions.

## Table of contents
- [Developer Guide](#developer-guide)
- [Code Contributions](#code-contributions)
- [Bug Reports](#bug-reports)

## Developer Guide
### Repository structure
The templates used for generating the [STACKIT Go SDK](https://github.com/stackitcloud/stackit-sdk-go) can found under `templates`. 

### Getting started

Check the [Getting Started](README.md#getting-started) section on the README.

#### Useful Make commands

These commands can be executed from the project root:

- `make project-tools`: get the required dependencies
- `make download-oas`: download the latest [REST API specs](https://github.com/stackitcloud/stackit-api-specifications) from the STACKIT services
- `make generate-sdk`: generate the SDK locally

## Code Contributions

To make your contribution, follow these steps:
1. Check open or recently closed [Pull Requests](https://github.com/stackitcloud/stackit-sdk-generator/pulls) and [Issues](https://github.com/stackitcloud/stackit-sdk-generator/issues) to make sure the contribution you are making has not been already tackled by someone else.
2. Fork the repo. 
3. Make your changes in a branch that is up-to-date with the original repo's `main` branch.
4. Commit your changes including a descriptive message.
5. Create a pull request with your changes.
6. The pull request will be reviewed by the repo maintainers. If you need to make further changes, make additional commits to keep commit history. When the PR is merged, commits will be squashed.

## Bug Reports
If you would like to report a bug, please open a [GitHub issue](https://github.com/stackitcloud/stackit-sdk-generator/issues/new).

To ensure we can provide the best support to your issue, follow these guidelines:

1. Go through the existing issues to check if your issue has already been reported.
2. Make sure you are using the latest version of the provider, we will not provide bug fixes for older versions. Also, latest versions may have the fix for your bug.
3. Please provide as much information as you can about your environment, e.g. your version of Go, your version of the provider, which operating system you are using and the corresponding version.
4. Include in your issue the steps to reproduce it, along with code snippets and/or information about your specific use case. This will make the support process much easier and efficient.

