# Stackit SDK Generator - Build Tool

Currently we have a lot of bash scripts to build the SDKs.
In the long term we want to reduce this because of readability issues.

New build functionality should be implemented in this tool.
And if we have some time we can also refactor the existing bash scripts to use this tool.

The end goal for this tool is to have a single entry point for building the SDKs.
Especially we want to leverage parallelism to speed up the build process.

## Status Quo

The build currently consists of multiple phases, split into multiple scripts:

- download oas
- generate sdk
- push pr

Information flows between these phases via files on disk.

This design has the advantage that during local devlopment on the build system itself, you can easily run a single phase without having to run the entire build process.

## Vision

This build tool should also support multiple phases.
The dependencies between phases should be modeled explicitly.
So that a call like `build push-pr` will automatically trigger all required phases before the `push-pr` phase.

It should be possible to skip phases that are up to date.
So if we run `build generate` the first time it would download OAS and generate the SDKs.
The second time it would only generate the SDKs, because the OAS files are already downloaded and up to date.

### Parallelism

The build tool should leverage parallelism to speed up the build process.
Currently most of the time is spent in the `generate` phase.
We serially call the SDK generator once for each service (including JVM startup).

A good first optimization would be to call the SDK generator once with the batch command:
https://openapi-generator.tech/docs/usage#batch

## Implemented Functionality

Currently only 3 standalone commands are implemented:

- plan.go: write a plan file, which services will be generated, which are blocked, which should be deleted
- generate.go: helper command to get oas-service-name, on-disk-service-name pairs from the plan file to generate
- delete.go: helper command to get on-disk-service-name from the plan file to delete

Language specific things like normalizing service names are implemented in languages.go
