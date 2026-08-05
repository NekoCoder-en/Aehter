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
}
subprojects {
    project.evaluationDependsOn(":app")

    if (project.name != "app") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }

    if (project.name != "app") {
        afterEvaluate {
            tasks.withType<JavaCompile>().configureEach {
                sourceCompatibility = "17"
                targetCompatibility = "17"
            }
            if (hasProperty("android")) {
                val androidExt = extensions.findByName("android")
                if (androidExt != null) {
                    try {
                        val method = androidExt.javaClass.getMethod("setCompileSdk", Int::class.java)
                        method.invoke(androidExt, 35)
                    } catch (e: Exception) {
                        try {
                            val method = androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java)
                            method.invoke(androidExt, 35)
                        } catch (e2: Exception) {}
                    }
                    try {
                        val compileOptions = androidExt.javaClass.getMethod("getCompileOptions").invoke(androidExt)
                        compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
                        compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
                    } catch (e: Exception) {}
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
