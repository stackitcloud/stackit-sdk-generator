[![Check API version lock](https://github.com/stackitcloud/stackit-sdk-generator/actions/workflows/check-api-versions.yaml/badge.svg)](https://github.com/stackitcloud/stackit-sdk-generator/actions/workflows/check-api-versions.yaml)

# Overview

This repository implements the automatic generation of client libraries to access STACKIT APIs. It is based on the [OpenAPI Generator](https://openapi-generator.tech/). The process' input are the REST API specs in the [OpenAPI Specification](https://github.com/OAI/OpenAPI-Specification) format (OAS), which are stored in [STACKIT API specifications](https://github.com/stackitcloud/stackit-api-specifications).

Currently only generation of Go libraries are supported. The output is stored in the [STACKIT GO SDK repo](https://github.com/stackitcloud/stackit-sdk-go).

## Getting started

If you want to modify script or templates and you can run code locally.

Requires `Go 1.21` or higher.

1. Set up the project and tools by running
   ```bash
   make project-tools
   ```
2. Download Open Api Specifications (OAS), that are the input for the SDK generation, by running
   ```bash
   make download-oas
   ```
   This step needs to be done only at the first start and when OAS updates are present.
3. Run the Go SDK generation for testing by
   ```bash
   make generate-go-sdk
   ```
   The output goes to the `./sdk-repo-updated` folder.
   1. Run the Python SDK generation for testing by
   ```bash
   make generate-python-sdk
   ```
   The output goes to the `./sdk-repo-updated` folder.
   2. Run the Java SDK generation for testing by
   ```bash
   make generate-java-sdk
   ```
   The output goes to the `./sdk-repo-updated` folder.

## Reporting issues

If you encounter any issues or have suggestions for improvements, please open an issue in the repository.

## Contribute

Your contribution is welcome! For more details on how to contribute, refer to our [Contribution Guide](./CONTRIBUTION.md).

## License

Apache 2.0
