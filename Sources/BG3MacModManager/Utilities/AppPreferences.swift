// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum AppPreferenceKey {
    static let lockModSettingsAfterSave = "lockModSettingsAfterSave"
    static let autoBackupBeforeSave = "autoBackupBeforeSave"
    static let backupRetentionDays = "backupRetentionDays"
    static let autoSaveBeforeLaunch = "autoSaveBeforeLaunch"
    static let autoSaveOnProfileLoad = "autoSaveOnProfileLoad"
    static let autoCheckNexusUpdates = "autoCheckNexusUpdates"

    /// Optional overrides for installations moved outside the standard macOS
    /// locations. Empty values deliberately mean “use the macOS default”.
    static let larianDocumentsPath = "larianDocumentsPath"
    static let steamAppsPath = "steamAppsPath"
    static let appSupportDirectoryPath = "appSupportDirectoryPath"
}

struct SavePreferences {
    let lockAfterSave: Bool
    let autoBackup: Bool
    let backupRetentionDays: Int

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            AppPreferenceKey.lockModSettingsAfterSave: true,
            AppPreferenceKey.autoBackupBeforeSave: true,
            AppPreferenceKey.backupRetentionDays: 30,
        ])
        lockAfterSave = defaults.bool(forKey: AppPreferenceKey.lockModSettingsAfterSave)
        autoBackup = defaults.bool(forKey: AppPreferenceKey.autoBackupBeforeSave)
        backupRetentionDays = defaults.integer(forKey: AppPreferenceKey.backupRetentionDays)
    }
}
