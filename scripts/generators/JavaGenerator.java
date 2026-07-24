import org.openapitools.codegen.languages.JavaClientCodegen;
import shared.PostProcessFileReplace;

import java.io.File;

public class JavaGenerator extends JavaClientCodegen {
    private static PostProcessFileReplace postProcessFileReplace = new PostProcessFileReplace("overrides/java");

    @Override
    public String getName() {
        return "JavaClientCodegen";
    }

    public JavaGenerator(){
        super();
        System.out.println("=== Custom Java Generator initialized ===");
    }

    @Override
    public void postProcessFile(File file, String fileType) {
        postProcessFileReplace.process(file);
        super.postProcessFile(file, fileType);
    }
}
