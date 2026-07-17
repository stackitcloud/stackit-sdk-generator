package shared;

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
import java.util.function.Function;
import java.util.stream.Collectors;

public class PostProcessFileReplace {
    private final String configPackage;
    private final Map<String, OverrideConfig> overrides;

    public PostProcessFileReplace(String configPackage) {
        this.configPackage = configPackage;
        try {
            overrides = OverrideConfig.load(configPackage).stream().collect(Collectors.toMap(
                    o -> o.path,
                    Function.identity()
            ));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    public void process(File file) {
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
                    var resource = Thread.currentThread().getContextClassLoader().getResource(configPackage + "/" + override.replacementPath);
                    if (resource == null) {
                        throw new IllegalStateException(
                                String.format("configure override file can't be found in resources, check configuration %s.replacementPath in overrides.properties and verify the file exists",
                                        override.name
                                )
                        );
                    }
                    var replacementPath = Path.of(resource.getPath());
                    var replacementContent = Files.readAllBytes(replacementPath);
                    Files.write(file.toPath(), replacementContent, StandardOpenOption.TRUNCATE_EXISTING);
                } else {
                    throw new IllegalStateException(
                            String.format("expected %s to hash to %s but got %s\nedit overrides.properties in the sdk-generator and update %s.hash to accept this change",
                                    override.path,
                                    override.hash,
                                    hash,
                                    override.name
                            )
                    );
                }
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }

    }

    private static class OverrideConfig {
        public String name;
        public String path;
        public String replacementPath;
        public String hash;

        public static List<OverrideConfig> load(String configPackage) throws IOException {
            var path = Thread.currentThread().getContextClassLoader().getResource(configPackage + "/overrides.properties").getPath();
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
