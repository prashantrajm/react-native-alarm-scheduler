import ExpoModulesCore
import Foundation

struct AlarmScheduleRecord: Record {
  @Field var id: String?
  @Field var hour: Int = -1
  @Field var minute: Int = -1
  @Field var title: String?
  @Field var weekdays: [Int]?
  @Field var timestamp: Double?
  @Field var showUi: Bool = false
  @Field var soundUri: String?
  @Field var ios: IosAlarmOptionsRecord?
}

struct IosAlarmOptionsRecord: Record {
  @Field var metadata: [String: Any]?
  @Field var alertTitle: String?
  @Field var alertActionMode: String?
  @Field var stopButtonTitle: String?
  @Field var secondaryButtonTitle: String?
  @Field var countdownTitle: String?
  @Field var stopIntentBehavior: String?
  @Field var secondaryButtonBehavior: String?
  @Field var soundUri: String?
  @Field var soundName: String?
  @Field var silent: Bool = false
}

final class InvalidAlarmException: Exception {
  // Not `message`: ExpoModulesCore 58 adds `open var message` to Exception, and SDK 57 has none to
  // override, so only a different name compiles against both.
  private let detail: String

  override var reason: String {
    detail
  }

  init(_ reason: String) {
    self.detail = reason
    super.init()
  }
}

final class UnsupportedAlarmException: Exception {
  // Not `message`: ExpoModulesCore 58 adds `open var message` to Exception, and SDK 57 has none to
  // override, so only a different name compiles against both.
  private let detail: String

  override var reason: String {
    detail
  }

  init(_ reason: String) {
    self.detail = reason
    super.init()
  }
}
