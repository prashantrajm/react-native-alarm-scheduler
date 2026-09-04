package expo.modules.alarm

import java.util.UUID

internal object AlarmSchedulerOccurrencePolicy {
  fun newPrimaryOccurrenceId(): String = UUID.randomUUID().toString()

  fun resolutionStorageKey(occurrenceId: String, idempotencyKey: String): String =
    "resolution:$occurrenceId:$idempotencyKey"
}
