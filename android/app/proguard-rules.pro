# R8 rules of the app, which the release build type of build.gradle.kts names.
#
# No rule is needed yet. The app has no Java or Kotlin code of its own that a name or reflection reaches, and R8
# already applies the rules that come with the libraries:
#
# - the rules of the Flutter tool for the embedding;
# - the consumer rules of the plugins: flutter_plugin_android_lifecycle (proguard.txt keeps
#   androidx.lifecycle.DefaultLifecycleObserver), jni and jni_flutter (consumer-rules.pro keeps their packages, which
#   the Dart bindings of path_provider_android call through JNI);
# - the consumer rules inside the AARs of the Firebase SDKs and of AndroidX.
#
# The other plugins with Android code (cloud_firestore, connectivity_plus, firebase_auth, firebase_core,
# firebase_storage, image_picker_android, printing, share_plus, sqflite_android) declare no consumer rules and call
# none of their classes by name.
#
# Add a rule here only for a class that R8 removes or renames and that a release build then cannot find.
