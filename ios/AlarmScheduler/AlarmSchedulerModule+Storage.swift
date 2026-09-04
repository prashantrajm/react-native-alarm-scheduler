import AVFoundation
import Foundation

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
#endif

extension AlarmSchedulerModule {
  func normalizeMetadata(_ metadata: [String: Any]?, id: String, title: String) -> [String: Any] {
    var normalized: [String: Any] = [:]
    metadata?.forEach { key, value in
      guard !key.isEmpty else {
        return
      }
      if let value = value as? String {
        normalized[key] = value
      } else if let value = value as? Bool {
        normalized[key] = value
      } else if let value = value as? Int {
        normalized[key] = value
      } else if let value = value as? Double {
        normalized[key] = value
      } else if let value = value as? Float {
        normalized[key] = Double(value)
      } else if let value = value as? NSNumber {
        normalized[key] = value
      }
    }
    normalized["alarmId"] = id
    normalized["title"] = title
    return normalized
  }

  func normalizedSoundName(_ soundName: String?) -> String? {
    guard let soundName = soundName?.trimmingCharacters(in: .whitespacesAndNewlines), !soundName.isEmpty else {
      return nil
    }
    return soundName
  }

  /**
   * AlarmKit resolves runtime sounds from Library/Sounds. Transcoding to a short PCM CAF makes
   * picker results such as MP3, M4A, WAV and AIFF conform to the system alert-sound contract.
   */
  func prepareRuntimeSound(uri: String, alarmId: String) throws -> String {
    guard let alarmId = UUID(uuidString: alarmId)?.uuidString.lowercased() else {
      throw InvalidAlarmException("Alarm id must be a UUID string on iOS.")
    }
    guard let sourceUrl = URL(string: uri), sourceUrl.isFileURL else {
      throw InvalidAlarmException("ios.soundUri must be a readable local file URI.")
    }

    let isSecurityScoped = sourceUrl.startAccessingSecurityScopedResource()
    defer {
      if isSecurityScoped {
        sourceUrl.stopAccessingSecurityScopedResource()
      }
    }

    let fileManager = FileManager.default
    guard let libraryUrl = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      throw InvalidAlarmException("Unable to locate the app Library directory.")
    }
    let soundsUrl = libraryUrl.appendingPathComponent("Sounds", isDirectory: true)
    do {
      try fileManager.createDirectory(at: soundsUrl, withIntermediateDirectories: true)
    } catch {
      throw InvalidAlarmException("Unable to create Library/Sounds: \(error.localizedDescription)")
    }

    let fileName = "alarm-scheduler-\(alarmId).caf"
    let destinationUrl = soundsUrl.appendingPathComponent(fileName)
    let temporaryUrl = fileManager.temporaryDirectory
      .appendingPathComponent("alarm-scheduler-\(alarmId)-\(UUID().uuidString).caf")
    do {
      let input = try AVAudioFile(forReading: sourceUrl)
      let format = input.processingFormat
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw InvalidAlarmException("The selected file does not contain readable audio.")
      }
      let output = try AVAudioFile(forWriting: temporaryUrl, settings: format.settings)
      var remainingFrames = min(input.length, AVAudioFramePosition(format.sampleRate * 29))
      while remainingFrames > 0 {
        let frameCount = AVAudioFrameCount(min(remainingFrames, 4096))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
          throw InvalidAlarmException("Unable to allocate an audio conversion buffer.")
        }
        try input.read(into: buffer, frameCount: frameCount)
        guard buffer.frameLength > 0 else {
          break
        }
        try output.write(from: buffer)
        remainingFrames -= AVAudioFramePosition(buffer.frameLength)
      }
      guard input.length > 0 else {
        throw InvalidAlarmException("The selected audio file is empty.")
      }
      if fileManager.fileExists(atPath: destinationUrl.path) {
        _ = try fileManager.replaceItemAt(destinationUrl, withItemAt: temporaryUrl)
      } else {
        try fileManager.moveItem(at: temporaryUrl, to: destinationUrl)
      }
    } catch let error as InvalidAlarmException {
      try? fileManager.removeItem(at: temporaryUrl)
      throw error
    } catch {
      try? fileManager.removeItem(at: temporaryUrl)
      throw InvalidAlarmException("Unable to import the selected alarm sound: \(error.localizedDescription)")
    }
    return fileName
  }

  func removeRuntimeSound(alarmId: String) {
    guard let alarmId = UUID(uuidString: alarmId)?.uuidString.lowercased(),
      let libraryUrl = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      return
    }
    let soundsUrl = libraryUrl.appendingPathComponent("Sounds", isDirectory: true)
    let prefix = "alarm-scheduler-\(alarmId)."
    let files = (try? FileManager.default.contentsOfDirectory(
      at: soundsUrl,
      includingPropertiesForKeys: nil
    )) ?? []
    for file in files where file.lastPathComponent.hasPrefix(prefix) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  func makeAlarmSound(_ soundName: String?) -> AlertConfiguration.AlertSound {
    guard let soundName = alarmSchedulerEffectiveSoundName(normalizedSoundName(soundName)) else {
      return .default
    }
    return .named(soundName)
  }
  #endif

  func alarmContext(from alarm: [String: Any], state: String, nativeAlarmId: String? = nil) -> [String: Any]? {
    guard let id = alarm["id"] as? String else {
      return nil
    }
    var context: [String: Any] = [
      "id": id,
      "metadata": alarm["metadata"] as? [String: Any] ?? normalizeMetadata(nil, id: id, title: alarm["title"] as? String ?? "Alarm"),
      "state": state
    ]
    if let nativeAlarmId {
      context["nativeAlarmId"] = nativeAlarmId
    }
    return context
  }

  func recentFiredAlarmContext(excluding activeIds: Set<String>) -> [String: Any]? {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let recentWindowMillis: Int64 = 60 * 60 * 1000
    return storedAlarms()
      .filter { alarm in
        guard
          let id = alarm["id"] as? String,
          let timestamp = alarmTimestamp(alarm["timestamp"])
        else {
          return false
        }
        let weekdays = alarm["weekdays"] as? [Int] ?? []
        return weekdays.isEmpty &&
          !activeIds.contains(id) &&
          timestamp <= now &&
          now - timestamp <= recentWindowMillis
      }
      .sorted {
        (alarmTimestamp($0["timestamp"]) ?? 0) > (alarmTimestamp($1["timestamp"]) ?? 0)
      }
      .compactMap { alarmContext(from: $0, state: "alerting") }
      .first
  }

  private func alarmTimestamp(_ value: Any?) -> Int64? {
    if let value = value as? Int64 {
      return value
    }
    if let value = value as? Int {
      return Int64(value)
    }
    if let value = value as? Double {
      return Int64(value)
    }
    if let value = value as? NSNumber {
      return value.int64Value
    }
    return nil
  }

  func nextTriggerTimestamp(hour: Int, minute: Int, weekdays: [Int]) -> Int64 {
    let calendar = Calendar.current
    let now = Date()
    for offset in 0..<14 {
      guard let day = calendar.date(byAdding: .day, value: offset, to: now) else {
        continue
      }
      var components = calendar.dateComponents([.year, .month, .day], from: day)
      components.hour = hour
      components.minute = minute
      components.second = 0
      guard let candidate = calendar.date(from: components), candidate > now else {
        continue
      }
      let weekday = isoWeekday(from: candidate)
      if weekdays.isEmpty || weekdays.contains(weekday) {
        return Int64(candidate.timeIntervalSince1970 * 1000)
      }
    }
    return Int64(now.addingTimeInterval(24 * 60 * 60).timeIntervalSince1970 * 1000)
  }

  private func isoWeekday(from date: Date) -> Int {
    let weekday = Calendar.current.component(.weekday, from: date)
    return weekday == 1 ? 7 : weekday - 1
  }

  func storedAlarms() -> [[String: Any]] {
    let defaults = UserDefaults.standard
    guard let store = defaults.dictionary(forKey: "alarm_scheduler_store") as? [String: [String: Any]] else {
      return []
    }
    return Array(store.values)
  }

  func save(alarm: [String: Any]) {
    var store = UserDefaults.standard.dictionary(forKey: "alarm_scheduler_store") as? [String: [String: Any]] ?? [:]
    if let id = alarm["id"] as? String {
      store[id] = alarm
      UserDefaults.standard.set(store, forKey: "alarm_scheduler_store")
    }
  }

  func remove(id: String) -> Bool {
    var store = UserDefaults.standard.dictionary(forKey: "alarm_scheduler_store") as? [String: [String: Any]] ?? [:]
    let existed = store.removeValue(forKey: id) != nil
    UserDefaults.standard.set(store, forKey: "alarm_scheduler_store")
    return existed
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  func mapAuthorizationStatus(_ status: AlarmManager.AuthorizationState) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 26.0, *)
  func mapAlarmState(_ state: Alarm.State) -> String {
    switch state {
    case .scheduled:
      return "scheduled"
    case .alerting:
      return "alerting"
    case .countdown:
      return "countdown"
    case .paused:
      return "paused"
    @unknown default:
      return "scheduled"
    }
  }

  @available(iOS 26.0, *)
  func alarmKitMetadataValues(_ metadata: [String: Any]) -> [String: AlarmSchedulerMetadataValue] {
    var values: [String: AlarmSchedulerMetadataValue] = [:]
    metadata.forEach { key, value in
      if let value = value as? String {
        values[key] = .string(value)
      } else if let value = value as? Bool {
        values[key] = .bool(value)
      } else if let value = value as? Int {
        values[key] = .number(Double(value))
      } else if let value = value as? Double {
        values[key] = .number(value)
      } else if let value = value as? Float {
        values[key] = .number(Double(value))
      } else if let value = value as? NSNumber {
        values[key] = .number(value.doubleValue)
      }
    }
    return values
  }
  #endif
}
