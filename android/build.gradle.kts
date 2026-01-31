plugins {
    id("com.google.gms.google-services") version "4.4.4" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ⭐ REQUIRED FIX FOR FIREBASE + AGP 8+ ⭐
// Firebase library modules define BuildConfig fields.
// AGP 8 disables BuildConfig by default — so we must enable it.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            buildFeatures {
                buildConfig = true  // ✅ FIX firebase_core, firebase_messaging, etc.
            }
        }
    }
}

// ⭐ REQUIRED FIX FOR OLD PLUGINS MISSING namespace (AGP 8+) ⭐
// This safely injects a namespace ONLY if the plugin forgot to define one.
// Prevents build failures for legacy plugins like google_mlkit_barcode_scanning 0.7.0
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (namespace == null) {
                namespace = "com.temp.${project.name.replace("-", "_")}"
            }
        }
    }
}

// ---- YOUR ORIGINAL BUILD DIR OVERRIDES ----
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
