import ExpoModulesCore
import Foundation

struct AlarmOccurrenceNextRecord: Record {
  @Field var delaySeconds: Double = 0
  @Field var relationship: String = ""
  @Field var metadata: [String: Any]?
}

struct AlarmOccurrenceResolutionRecord: Record {
  @Field var outcome: String = ""
  @Field var next: AlarmOccurrenceNextRecord?
  @Field var idempotencyKey: String?
}
