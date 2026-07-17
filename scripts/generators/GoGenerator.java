import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.parameters.Parameter;
import org.openapitools.codegen.CodegenParameter;
import org.openapitools.codegen.CodegenProperty;
import org.openapitools.codegen.languages.GoClientCodegen;
import shared.PostProcessFileReplace;

import java.io.File;
import java.util.Set;

public class GoGenerator extends GoClientCodegen {
    private static RegionFix regionFix = new RegionFix();
    private static PostProcessFileReplace postProcessFileReplace = new PostProcessFileReplace("overrides/go");

    @Override
    public String getName() {
        return "GoClientCodegen";
    }

    public GoGenerator(){
        super();
        System.out.println("=== Custom Go Generator initialized ===");
    }

    @Override
    public CodegenProperty fromProperty(String name, Schema p, boolean required) {
        return regionFix.fromProperty(super.fromProperty(name, p, required));
    }

    @Override
    public CodegenParameter fromParameter(Parameter parameter, Set<String> imports) {
        return regionFix.fromParameter(super.fromParameter(parameter, imports));
    }

    @Override
    public void postProcessFile(File file, String fileType) {
        postProcessFileReplace.process(file);
        super.postProcessFile(file, fileType);
    }
}

class RegionFix {
    CodegenProperty fromProperty(CodegenProperty property) {
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

    CodegenParameter fromParameter(CodegenParameter parameter) {
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

    private static boolean isRegionField(String name) {
        if (name == null) {
            return false;
        }
        return name.equalsIgnoreCase("region") || name.equalsIgnoreCase("regionId");
    }
}
