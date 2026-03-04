# STACKIT Golang SDK Generator

## Template adjustments

The following templates were customized but don't need to be adjusted when updating the Go SDK generator to a new a newer upstream version:

- `configuration.mustache`: This template was entirely overwritten so we can use our custom [configuration struct](https://github.com/stackitcloud/stackit-sdk-go/blob/c3b04bc3cb8bf93de351fd7b1b04ac11de78ff89/core/config/config.go#L78) from our Go SDK core module. By default the OpenAPI generator would generate a new configuration struct for each service API version.

The following templates were customized and need to be checked for adjustments when updating the Go SDK generator to a newer upstream version:

- `client.mustache`: 
  - Removed the generation of the `GenericOpenAPIError` struct which would be generated for each service API version by default. Instead use the `GenericOpenAPIError` struct from the [Go SDK core module](https://github.com/stackitcloud/stackit-sdk-go/blob/c3b04bc3cb8bf93de351fd7b1b04ac11de78ff89/core/oapierror/oapierror.go#L15).
    - Our custom `GenericOpenAPIError` struct from the core module has additional fields like the http status code, ... which the default one doesn't have.
  - Customized the `NewAPIClient` func to use the configuration struct and the authentication from the core SDK module.
- `api.mustache`
  - Added customization to capture the HTTP request and response in the context (like it was done before the multi API version support was implemented in the Go SDK generator).
  - Use the `GenericOpenAPIError` struct from the core module instead of the default one (see previous section of `client.mustache`).
  - Don't return the `http.Response` param which the OpenAPI generator returns by default.
    - It was done like that before the multi API version support was implemented in the Go SDK generator.
    - Furthermore, it would when using the STACKIT Go SDK require a lot of boilerplate code after each SDK API call to do a nil check, close the http response body and handle the potential error.

## Custom templates

The custom templates don't need to be adjusted when updating the Go SDK generator to a new a newer upstream version.

- `custom/api_mock.mustache`: This template was added to allow easy mocking of SDK API calls in unit test implementations.

