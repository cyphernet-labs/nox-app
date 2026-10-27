package com.cyphernetlabs.nox_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.security.KeyStore

class MainActivity : FlutterActivity() {
    /** The file the open save dialog saves, and the answer it owes; one dialog at a time. */
    private var pendingSave: Pair<String, MethodChannel.Result>? = null

    /**
     * The system back on the last screen sends the app to the background rather
     * than finishing it - the "minimize" of the spec (4.1 on the Chats tab, the
     * blocking error 3.1), and what Android itself does for a launcher activity
     * since 12. FlutterActivity would finish(): the engine torn down, the next
     * tap a cold start through the splash with the connection dialled again.
     */
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nox/save").setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> showSaveDialog(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The save dialog of the file view (5.3): the system's "create document",
     * into which the plain copy of the file (phase 048) is then written.
     * file_selector has no save dialog on Android - its getSaveLocation is not
     * implemented there.
     */
    private fun showSaveDialog(path: String?, result: MethodChannel.Result) {
        if (path == null) {
            result.error("save", "no path", null)
            return
        }
        if (pendingSave != null) {
            result.error("busy", null, null)
            return
        }
        val name = File(path).name
        val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(type)
            .putExtra(Intent.EXTRA_TITLE, name)
        try {
            startActivityForResult(intent, SAVE_REQUEST)
        } catch (e: ActivityNotFoundException) {
            result.error("save", e.javaClass.simpleName, null)
            return
        }
        pendingSave = path to result
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val (path, result) = pendingSave ?: return
        pendingSave = null
        val target = data?.data
        if (resultCode != RESULT_OK || target == null) {
            result.success(false)
            return
        }
        // Off the main thread: a video runs to hundreds of megabytes.
        Thread {
            try {
                FileInputStream(path).use { input ->
                    val output = contentResolver.openOutputStream(target, "w") ?: throw IOException("no output stream")
                    output.use { input.copyTo(it, 64 * 1024) }
                }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                // Half a file is not a saved file.
                try {
                    DocumentsContract.deleteDocument(contentResolver, target)
                } catch (ignored: Exception) {
                }
                // The class only: a message could name the path.
                runOnUiThread { result.error("save", e.javaClass.simpleName, null) }
            }
        }.start()
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

    private companion object {
        /** The save dialog's request; well away from the codes the plugins use. */
        const val SAVE_REQUEST = 0x4E53
    }
}
