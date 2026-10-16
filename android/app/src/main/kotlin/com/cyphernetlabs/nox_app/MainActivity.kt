package com.cyphernetlabs.nox_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nox/secure_store").setMethodCallHandler { call, result ->
            when (call.method) {
                "wipe" -> try {
                    wipeSecureStore()
                    result.success(true)
                } catch (e: Exception) {
                    // The class only: a message could name a key alias.
                    result.error("wipe", e.javaClass.simpleName, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The secure-store plugin's store, gone whole: its Keystore entries and its
     * preference files. The plugin rebuilds a store only from a key it can no
     * longer unwrap; a key that is there but cannot be read at all (a key blob
     * an update damaged) fails every call, deletes included, and only this
     * gets the app out of it. deleteEntry works where getKey throws. The plugin
     * makes a new key and new files at its next call.
     */
    private fun wipeSecureStore() {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        for (alias in keyStore.aliases().toList()) {
            if (alias.contains("FlutterSecureStoragePlugin") || alias == "_androidx_security_master_key_") {
                keyStore.deleteEntry(alias)
            }
        }
        val prefs = File(applicationInfo.dataDir, "shared_prefs")
        prefs.listFiles()
            ?.filter { it.name.startsWith("FlutterSecure") && it.name.endsWith(".xml") }
            ?.forEach { deleteSharedPreferences(it.name.removeSuffix(".xml")) }
    }
}
