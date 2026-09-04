package expo.modules.alarm

import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class AlarmOccurrenceNextRecord : Record {
  @Field var delaySeconds: Double = 0.0
  @Field var relationship: String = ""
  @Field var metadata: Map<String, Any>? = null
}

class AlarmOccurrenceResolutionRecord : Record {
  @Field var outcome: String = ""
  @Field var next: AlarmOccurrenceNextRecord? = null
  @Field var idempotencyKey: String? = null
}
