# Custom Generators

Customized templates are painful when updating the generator. Each template has to be compared with upstream and adapted
accordingly.

We use custom generators for introducing workarounds and fixes to not further customize our templates.

## Structure

Custom generators live in this directory. For each language with a custom generator there should be a `<lang>Generator.java`
file. Each fix/workaround should live in its own class and be called from the `<lang>Generator.java` file. This allows
easy removal of such fixes, when they are no longer needed.

Fixes, applicable to multiple languages, should be implemented in the `shared` package.

We try to only use the JDK and no external libraries besides the `openapi-generator` itself to keep a simple build step.

## How Custom Generators are executed

Each language with a custom generator, needs an adapted `<lang>.sh` script. Before building each service the custom
generator has to be built:

```bash
# compile custom generator
cd ${ROOT_DIR}
mkdir -p custom
javac -cp "${GENERATOR_JAR_PATH}" -d custom $(find ./scripts/generators -type f -name '*.java' | grep -v overrides)
```

This compiles all java files into the `custom` directory. Here we also exclude java files in the `overrides` directory.
These are resources and should not be compiled in this step.

The generator call itself has to be adapted:

```bash
java  -Dlog.level="${GENERATOR_LOG_LEVEL}" -cp "custom:${GENERATOR_JAR_PATH}:scripts/generators" \
    org.openapitools.codegen.OpenAPIGenerator generate \
    --generator-name JavaGenerator \
    --enable-post-process-file \
    # more params
```

We have to:
- extend the classpath: `custom` makes the compiled custom generator available, `scripts/genrators` the `overrides`
  resources
- the `generator-name` needs to be changed to the fully-qualified class name of the custom generator
- `enable-post-process-file` has to be activated to support `overrides`

## Implemented Fixes

### Go: Region Param Adjustment

- we use `RESOLVE_INLINE_ENUMS`
- this creates model classes for inline enums
- this leads to a lot of different types for region enums with the same options
- which makes the API hard to use
- we force a string parameter instead

### Go/Java: Overrides

- there are some usages of `oneOf` schemas in our API specs, that are correct schema wise, but the generated code fails
- example: `{ "type": "cidrv4", "value": string }`, `{ "type": "cidrv6", "value": string }` both, have the same shape
- but they use different patterns for `value`
- some language generators do not apply the pattern when validating the `oneOf` and report a false positive violation
- fixing this upstream would be very involved
- we fix it by replacing after generating sources, by replacing files

How to configure an override:
- edit the `overrides.properties` file for the language in question
- to override a single file you need 3 properties: `<name>.path`, `<name>.replacementPath` and `<name>.hash`
- `<name>` has to be equal for all 3 properties
- `path` is used to match the generated file, which should be replaced
- `hash` is used to check that the generated file still has the same content as when the override was configured
- `replacementPaht` specifies the file in resources, that should be used as replacemen