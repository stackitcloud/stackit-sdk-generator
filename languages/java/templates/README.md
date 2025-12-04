# Java templates

This folder contains only our customized Java templates. Beside these customized templates,
the original templates of openapi-generator for Java are used. These can be found in the
official GitHub repo of the [openapi-generator](https://github.com/OpenAPITools/openapi-generator/tree/v7.14.0/modules/openapi-generator/src/main/resources/Java).

If you need to change something in the Java Generator, try always first to add
[user-defined templates](https://openapi-generator.tech/docs/customization#user-defined-templates),
instead of overwriting existing templates. These ensure an easier upgrade process, to newer
versions of the openapi-generator.

If it's required to customize the original templates, you can copy them into this directory.  
Try to minimize the customization as much as possible, to ensure, that we can easily upgrade
to newer versions in the future.  
