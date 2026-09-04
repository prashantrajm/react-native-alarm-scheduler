package expo.modules.alarm

import android.content.Context
import org.json.JSONObject
import java.util.UUID
import kotlin.math.max
import kotlin.math.roundToLong

internal object AlarmSchedulerOccurrenceManager {
  fun resolve(
    context: Context,
    occurrenceId: String,
    resolution: AlarmOccurrenceResolutionRecord
  ): Map<String, Any> {
    require(occurrenceId.isNotBlank()) { "occurrenceId must not be empty." }
    require(resolution.outcome == "completed" || resolution.outcome == "deferred") {
      "outcome must be completed or deferred."
    }
    val next = resolution.next
    if (resolution.outcome == "deferred") {
      require(next != null && next.relationship == "deferred") {
        "A deferred resolution requires a deferred next occurrence."
      }
    }
    if (next != null) {
      require(next.relationship == "deferred" || next.relationship == "followUp") {
        "next.relationship must be deferred or followUp."
      }
      require(next.delaySeconds.isFinite() && next.delaySeconds > 0) {
        "next.delaySeconds must be greater than zero."
      }
    }

    val alarmId = AlarmSchedulerOccurrenceStore.alarmId(context, occurrenceId)
    resolution.idempotencyKey?.takeIf(String::isNotBlank)?.let { key ->
      AlarmSchedulerOccurrenceStore.resolution(context, alarmId, key)?.let {
        return AlarmSchedulerJson.toMap(it)
      }
    }
    val stored = AlarmSchedulerStore.alarm(context, alarmId)
      ?: throw IllegalStateException("No alarm definition exists for occurrence $occurrenceId.")

    AlarmSchedulerStore.complete(context, alarmId)
    AlarmSchedulerScheduler.cancelBackups(context, alarmId)
    AlarmSchedulerRingService.complete(context, alarmId)
    AlarmSchedulerStore.clearActionsForAlarm(context, alarmId)
    AlarmSchedulerOccurrenceStore.updatePhase(context, occurrenceId, "completed")

    var nextOccurrence: JSONObject? = null
    var status = "resolved"
    if (next != null) {
      AlarmSchedulerStore.resetCompletion(context, alarmId)
      val nextOccurrenceId = UUID.randomUUID().toString()
      val scheduledFor = System.currentTimeMillis() + (max(0.1, next.delaySeconds) * 1000).roundToLong()
      val metadata = JSONObject(stored.optJSONObject("metadata")?.toString() ?: "{}")
      val occurrenceMetadata = AlarmSchedulerJson.fromMap(next.metadata)
      occurrenceMetadata.keys().forEach { key -> metadata.put(key, occurrenceMetadata.opt(key)) }
      metadata.put("occurrenceId", nextOccurrenceId)
      metadata.put("relationship", next.relationship)
      val occurrence = JSONObject()
        .put("occurrenceId", nextOccurrenceId)
        .put("alarmId", alarmId)
        .put("parentOccurrenceId", occurrenceId)
        .put("scheduledFor", scheduledFor)
        .put("relationship", next.relationship)
        .put("phase", "scheduled")
        .put("metadata", metadata)
      AlarmSchedulerOccurrenceStore.save(context, occurrence)
      if (AlarmSchedulerScheduler.scheduleRelatedOccurrence(context, alarmId, nextOccurrenceId, scheduledFor)) {
        nextOccurrence = occurrence
        AlarmSchedulerEventBus.emitStateChange(alarmId, "countdown", metadata, occurrence)
      } else {
        AlarmSchedulerOccurrenceStore.updatePhase(context, nextOccurrenceId, "cancelled")
        AlarmSchedulerStore.complete(context, alarmId)
        status = "resolvedWithoutNext"
      }
    }

    if (next == null || nextOccurrence == null) {
      val weekdays = AlarmSchedulerJson.intList(stored.optJSONArray("weekdays"))
      if (weekdays.isEmpty()) {
        AlarmSchedulerStore.removeAlarm(context, alarmId)
        AlarmSchedulerSoundStore.delete(context, alarmId)
      }
    }

    val result = JSONObject()
      .put("alarmId", alarmId)
      .put("resolvedOccurrenceId", occurrenceId)
      .put("outcome", resolution.outcome)
      .put("status", status)
    nextOccurrence?.let { result.put("nextOccurrence", it) }
    resolution.idempotencyKey?.takeIf(String::isNotBlank)?.let { key ->
      AlarmSchedulerOccurrenceStore.saveResolution(context, alarmId, key, result)
    }
    return AlarmSchedulerJson.toMap(result)
  }

  fun cancel(context: Context, occurrenceId: String): Boolean {
    val occurrence = AlarmSchedulerOccurrenceStore.occurrence(context, occurrenceId) ?: return false
    if (occurrence.optString("phase") == "completed" || occurrence.optString("phase") == "cancelled") {
      return false
    }
    val alarmId = occurrence.optString("alarmId")
    AlarmSchedulerScheduler.cancelRelatedOccurrence(context, alarmId, occurrenceId)
    AlarmSchedulerOccurrenceStore.updatePhase(context, occurrenceId, "cancelled")
    val hasAnotherActiveOccurrence = AlarmSchedulerOccurrenceStore.all(context, alarmId).any {
      it.optString("occurrenceId") != occurrenceId &&
        it.optString("relationship") != "primary" &&
        (it.optString("phase") == "scheduled" || it.optString("phase") == "ringing")
    }
    if (!hasAnotherActiveOccurrence) {
      AlarmSchedulerStore.complete(context, alarmId)
      AlarmSchedulerStore.alarm(context, alarmId)?.let { stored ->
        if (AlarmSchedulerJson.intList(stored.optJSONArray("weekdays")).isEmpty()) {
          AlarmSchedulerStore.removeAlarm(context, alarmId)
          AlarmSchedulerSoundStore.delete(context, alarmId)
        }
      }
    }
    return true
  }
}
