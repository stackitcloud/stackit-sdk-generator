package cloud.stackit.codegen;

import org.openapitools.codegen.CodegenProperty;
import org.openapitools.codegen.languages.GoClientCodegen;

import org.openapitools.codegen.CodegenParameter;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.parameters.Parameter;

public class CustomRegionGenerator extends GoClientCodegen {
    private final static String NAMESPACE = "cloud/stackit/codegen/";
    private final Map<String, OverrideConfig> overrides;

    @Override
    public String getName() {
        // This is the name you will pass to the -g flag
        return "cloud.stackit.codegen.CustomRegionGenerator";
    }

    public CustomRegionGenerator() {
        super();
        System.out.println("=== CUSTOM GO CLIENT GENERATOR INITIALIZED ===");
        try {
            overrides = OverrideConfig.load().stream().collect(Collectors.toMap(
                    o -> o.path,
                    Function.identity()
            ));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
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

    @Override
    public void postProcessFile(File file, String fileType) {
        var path = file.getAbsolutePath();
        var servicesIdx = path.indexOf("/services/");
        var subPath = path.substring(servicesIdx + "/services/".length());
        if (overrides.containsKey(subPath)) {
            var override = overrides.get(subPath);
            try {
                var content = Files.readAllBytes(file.toPath());
                var digest = MessageDigest.getInstance("MD5");
                var hex = HexFormat.of();
                var hash = hex.formatHex(digest.digest(content));
                if (hash.equals(override.hash)) {
                    var replacementPath = Path.of(Thread.currentThread().getContextClassLoader().getResource(NAMESPACE + override.replacementPath).getPath());
                    var replacementContent = Files.readAllBytes(replacementPath);
                    Files.write(file.toPath(), replacementContent, StandardOpenOption.TRUNCATE_EXISTING);
                } else {
                    throw new IllegalStateException(
                            "expected iaas/v2api/model_area_id.go to hash to " +
                                    override.hash + " but got " + hash +
                                    "\nedit CustomRegionGenerator.java in the sdk-generator and update IAAS_AREA_ID_HASH" +
                                    "to accept this change"
                    );
                }
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
        super.postProcessFile(file, fileType);
    }

    private static class OverrideConfig {
        public String name;
        public String path;
        public String replacementPath;
        public String hash;

        public static List<OverrideConfig> load() throws IOException {
            var path = Thread.currentThread().getContextClassLoader().getResource(NAMESPACE + "overrides.properties").getPath();
            var overrideProps = new Properties();
            overrideProps.load(new FileInputStream(path));
            var byName = new HashMap<String, OverrideConfig>();
            overrideProps.stringPropertyNames().forEach(key -> {
                var prefixLen = key.indexOf('.');
                var prefix = key.substring(0, prefixLen);
                var config = byName.computeIfAbsent(prefix, (_) -> new OverrideConfig());
                config.name = prefix;
                var suffix = key.substring(prefixLen + 1);
                switch (suffix) {
                    case "path" -> config.path = overrideProps.getProperty(key);
                    case "replacementPath" -> config.replacementPath = overrideProps.getProperty(key);
                    case "hash" -> config.hash = overrideProps.getProperty(key);
                    default -> throw new IllegalStateException("unexpected suffix: " + suffix);
                }
            });
            return byName.values().stream().toList();
        }
    }

}
