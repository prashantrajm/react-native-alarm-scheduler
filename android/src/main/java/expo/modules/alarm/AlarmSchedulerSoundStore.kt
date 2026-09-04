package expo.modules.alarm

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.security.MessageDigest

/** Copies picker-backed audio into app-owned storage so alarms never depend on a transient grant. */
internal object AlarmSchedulerSoundStore {
  private const val DIRECTORY_NAME = "alarm-scheduler-sounds"
  private const val FILE_PREFIX = "alarm-scheduler-"

  fun import(context: Context, alarmId: String, source: String): Uri {
    val sourceUri = Uri.parse(source)
    val directory = File(context.filesDir, DIRECTORY_NAME)
    check(directory.exists() || directory.mkdirs()) { "Unable to create alarm sound storage." }

    val baseName = "$FILE_PREFIX${digest(alarmId)}"
    val extension = sourceExtension(context, sourceUri)
    val destination = File(directory, if (extension == null) baseName else "$baseName.$extension")
    if (sourceUri.scheme == "file" && File(sourceUri.path.orEmpty()).canonicalFile == destination.canonicalFile) {
      return Uri.fromFile(destination)
    }

    // Keep the in-progress file outside the managed sound prefix. `delete` intentionally removes
    // every existing extension for this alarm ID, so using "$baseName.importing" here would make
    // it delete the file we just wrote before it can replace the destination.
    val temporary = File(directory, ".$baseName.importing")
    runCatching { temporary.delete() }
    val input = context.contentResolver.openInputStream(sourceUri)
      ?: throw IllegalArgumentException("Unable to read alarm sound URI: $source")
    try {
      input.use { sourceStream ->
        temporary.outputStream().use(sourceStream::copyTo)
      }
      delete(context, alarmId)
      temporary.copyTo(destination, overwrite = true)
    } catch (error: Exception) {
      throw IllegalArgumentException("Unable to import alarm sound URI: $source", error)
    } finally {
      runCatching { temporary.delete() }
    }
    return Uri.fromFile(destination)
  }

  fun delete(context: Context, alarmId: String) {
    val directory = File(context.filesDir, DIRECTORY_NAME)
    val prefix = "$FILE_PREFIX${digest(alarmId)}"
    directory.listFiles()?.filter { it.name == prefix || it.name.startsWith("$prefix.") }?.forEach {
      runCatching { it.delete() }
    }
  }

  private fun sourceExtension(context: Context, uri: Uri): String? {
    val displayName = runCatching {
      context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
      }
    }.getOrNull()
    val fromName = (displayName ?: uri.lastPathSegment)
      ?.substringAfterLast('.', "")
      ?.lowercase()
      ?.takeIf { it.matches(Regex("[a-z0-9]{1,10}")) }
    if (fromName != null) {
      return fromName
    }
    return context.contentResolver.getType(uri)
      ?.let(MimeTypeMap.getSingleton()::getExtensionFromMimeType)
      ?.lowercase()
      ?.takeIf { it.matches(Regex("[a-z0-9]{1,10}")) }
  }

  private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray())
    .take(12)
    .joinToString("") { "%02x".format(it) }
}
