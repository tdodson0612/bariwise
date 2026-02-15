# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve the line number information for debugging stack traces
-keepattributes SourceFile,LineNumberTable

# Hide the original source file name
-renamesourcefileattribute SourceFile

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.ads.**

# Amplify
-keep class com.amplifyframework.** { *; }
-keep class com.amazonaws.** { *; }
-dontwarn com.amplifyframework.**
-dontwarn com.amazonaws.**

# Supabase / Realtime / Ktor
-keep class io.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**

# Camera plugin
-keep class io.flutter.plugins.camera.** { *; }

# Image picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# Barcode scanning / ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Shared preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Path provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Device info
-keep class io.flutter.plugins.deviceinfo.** { *; }

# Package info
-keep class io.flutter.plugins.packageinfo.** { *; }

# URL launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Share plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# Local notifications
-keep class com.dexterous.** { *; }

# WebView
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep all enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelables
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Don't obfuscate classes with @Keep annotation
-keep @androidx.annotation.Keep class * {*;}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}

# Don't warn about missing classes
-dontwarn kotlin.**
-dontwarn org.slf4j.**
-dontwarn org.apache.commons.**