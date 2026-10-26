import Foundation

/// The pure rules behind a ring hold. Every path errs towards a loud ring: anything lapsed or
/// completed is not a hold.
enum AlarmSchedulerRingHoldPolicy {
  static let defaultSeconds: Double = 30
  static let minimumSeconds: Double = 5
  static let maximumSeconds: Double = 300
  /// A ringing occurrence older than this is stale, so holding it would create a ring, not quiet one.
  static let ringingWindowMillis: Int64 = 60 * 60 * 1000

  static func seconds(_ requested: Double?) -> Double {
    guard let requested, requested.isFinite else {
      return defaultSeconds
    }
    return min(max(requested, minimumSeconds), maximumSeconds)
  }

  static func isHeld(heldUntil: Int64?, isComplete: Bool, now: Int64) -> Bool {
    guard let heldUntil, !isComplete else {
      return false
    }
    return heldUntil > now
  }

  static func isRecentlyRinging(scheduledFor: Int64, now: Int64) -> Bool {
    scheduledFor <= now && now - scheduledFor <= ringingWindowMillis
  }
}
