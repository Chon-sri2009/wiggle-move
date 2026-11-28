import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    // Keep every plugin's Kotlin jvmTarget aligned with its Java targetCompatibility
    // (e.g. tflite_flutter compiles Java 11 while AGP 9 defaults Kotlin to the runner JDK).
    tasks.withType(KotlinCompile::class.java).configureEach {
        val kotlinTaskName = name
        compilerOptions.jvmTarget.set(
            project.provider {
                val javaTask =
                    project.tasks.findByName(kotlinTaskName.replace("Kotlin", "JavaWithJavac"))
                        as? JavaCompile
                val raw = javaTask?.targetCompatibility
                    ?: project.tasks.withType(JavaCompile::class.java).firstOrNull()?.targetCompatibility
                    ?: "17"
                JvmTarget.fromTarget(if (raw == "8") "1.8" else raw)
            },
        )
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
