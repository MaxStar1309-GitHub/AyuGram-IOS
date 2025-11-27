import Foundation
import SwiftSignalKit
import Postbox

// MARK: - AyuGram Settings Model
public struct AyuGramSettings: Codable, Equatable {
    // Ghost Mode Settings
    public var ghostModeEnabled: Bool
    public var preventReadReceipts: Bool
    public var preventOnlineStatus: Bool
    public var preventTypingStatus: Bool
    public var preventVoicePlayback: Bool
    public var preventVideoPlayback: Bool
    
    // Message History Settings
    public var saveDeletedMessages: Bool
    public var saveEditedMessages: Bool
    
    // Scheduled Send Settings
    public var useScheduledSend: Bool
    public var scheduledSendDelay: Int32 // в секундах, по умолчанию 12
    
    // Privacy Settings
    public var allowForwardFromPrivate: Bool
    public var allowSaveFromPrivate: Bool
    
    // Self-Destructing Media
    public var interceptSelfDestructing: Bool
    
    public static var `default`: AyuGramSettings {
        return AyuGramSettings(
            ghostModeEnabled: false,
            preventReadReceipts: true,
            preventOnlineStatus: true,
            preventTypingStatus: true,
            preventVoicePlayback: true,
            preventVideoPlayback: true,
            saveDeletedMessages: false,
            saveEditedMessages: false,
            useScheduledSend: false,
            scheduledSendDelay: 12,
            allowForwardFromPrivate: false,
            allowSaveFromPrivate: false,
            interceptSelfDestructing: false
        )
    }
    
    public init(
        ghostModeEnabled: Bool,
        preventReadReceipts: Bool,
        preventOnlineStatus: Bool,
        preventTypingStatus: Bool,
        preventVoicePlayback: Bool,
        preventVideoPlayback: Bool,
        saveDeletedMessages: Bool,
        saveEditedMessages: Bool,
        useScheduledSend: Bool,
        scheduledSendDelay: Int32,
        allowForwardFromPrivate: Bool,
        allowSaveFromPrivate: Bool,
        interceptSelfDestructing: Bool
    ) {
        self.ghostModeEnabled = ghostModeEnabled
        self.preventReadReceipts = preventReadReceipts
        self.preventOnlineStatus = preventOnlineStatus
        self.preventTypingStatus = preventTypingStatus
        self.preventVoicePlayback = preventVoicePlayback
        self.preventVideoPlayback = preventVideoPlayback
        self.saveDeletedMessages = saveDeletedMessages
        self.saveEditedMessages = saveEditedMessages
        self.useScheduledSend = useScheduledSend
        self.scheduledSendDelay = scheduledSendDelay
        self.allowForwardFromPrivate = allowForwardFromPrivate
        self.allowSaveFromPrivate = allowSaveFromPrivate
        self.interceptSelfDestructing = interceptSelfDestructing
    }
}

// MARK: - AyuGram Settings Manager
public final class AyuGramSettingsManager {
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    
    public init(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.accountManager = accountManager
    }
    
    public func getSettings() -> Signal<AyuGramSettings, NoError> {
        return accountManager.transaction { transaction -> AyuGramSettings in
            if let entry = transaction.getSharedData(ApplicationSpecificSharedDataKeys.ayuGramSettings)?.get(AyuGramSettings.self) {
                return entry
            } else {
                return .default
            }
        }
    }
    
    public func updateSettings(_ settings: AyuGramSettings) -> Signal<Void, NoError> {
        return accountManager.transaction { transaction -> Void in
            transaction.updateSharedData(ApplicationSpecificSharedDataKeys.ayuGramSettings, { _ in
                return PreferencesEntry(settings)
            })
        }
    }
    
    public func updateGhostMode(enabled: Bool) -> Signal<Void, NoError> {
        return self.getSettings()
        |> mapToSignal { settings in
            var updated = settings
            updated.ghostModeEnabled = enabled
            return self.updateSettings(updated)
        }
    }
    
    public func updateSaveDeletedMessages(enabled: Bool) -> Signal<Void, NoError> {
        return self.getSettings()
        |> mapToSignal { settings in
            var updated = settings
            updated.saveDeletedMessages = enabled
            return self.updateSettings(updated)
        }
    }
    
    public func updateSaveEditedMessages(enabled: Bool) -> Signal<Void, NoError> {
        return self.getSettings()
        |> mapToSignal { settings in
            var updated = settings
            updated.saveEditedMessages = enabled
            return self.updateSettings(updated)
        }
    }
    
    public func updateScheduledSend(enabled: Bool, delay: Int32? = nil) -> Signal<Void, NoError> {
        return self.getSettings()
        |> mapToSignal { settings in
            var updated = settings
            updated.useScheduledSend = enabled
            if let delay = delay {
                updated.scheduledSendDelay = delay
            }
            return self.updateSettings(updated)
        }
    }
}

// MARK: - Shared Data Keys Extension
extension ApplicationSpecificSharedDataKeys {
    public static let ayuGramSettings = ApplicationSpecificSharedDataKey(id: "ayuGramSettings")
}
