package cloud.stackit.codegen;

import org.openapitools.codegen.CodegenProperty;
import org.openapitools.codegen.languages.GoClientCodegen;

import org.openapitools.codegen.CodegenParameter;

import java.util.Set;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.parameters.Parameter;

public class CustomRegionGenerator extends GoClientCodegen {

    @Override
    public String getName() {
        // This is the name you will pass to the -g flag
        return "cloud.stackit.codegen.CustomRegionGenerator";
    }

    public CustomRegionGenerator() {
        super();
        System.out.println("=== CUSTOM GO CLIENT GENERATOR INITIALIZED ===");
    }

    @Override
    public CodegenProperty fromProperty(String name, Schema p, boolean required) {
        CodegenProperty property = super.fromProperty(name, p, required);

        if (isRegionField(property.name)) {
            property.dataType = "string";
            property.datatypeWithEnum = "string";
            property.baseType = "string";

            // Force template engine to treat this as a string
            property.isString = true;
            property.isInteger = false;
            property.isLong = false;
            property.isNumber = false;
            property.isNumeric = false;
        }
        return property;
    }

    /**
     * Intercepts operation parameters (query, path, header, body).
     */
    @Override
    public CodegenParameter fromParameter(Parameter param, Set<String> imports) {
        CodegenParameter parameter = super.fromParameter(param, imports);

        if (isRegionField(parameter.paramName)) {
            parameter.dataType = "string";

            // Force template engine to treat this as a string
            parameter.isString = true;
            parameter.isInteger = false;
            parameter.isLong = false;
            parameter.isNumber = false;
            // If it was previously an enum or another complex type, clear it
            parameter.isEnum = false;
        }
        return parameter;
    }

    private boolean isRegionField(String name) {
        if (name == null) {
            return false;
        }
        return name.equalsIgnoreCase("region") || name.equalsIgnoreCase("regionId");
    }
}
