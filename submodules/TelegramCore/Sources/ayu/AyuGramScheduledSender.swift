import Foundation
import SwiftSignalKit
import Postbox

// MARK: - Scheduled Message Sender
public final class AyuGramScheduledSender {
    private let settingsManager: AyuGramSettingsManager
    private var currentSettings: AyuGramSettings
    private var scheduledMessages: [ScheduledMessageInfo] = []
    private var timer: SwiftSignalKit.Timer?
    
    public init(settingsManager: AyuGramSettingsManager) {
        self.settingsManager = settingsManager
        self.currentSettings = .default
        
        // Загружаем настройки
        let _ = (settingsManager.getSettings()
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.currentSettings = settings
            self?.updateTimer()
        })
    }
    
    // MARK: - Message Scheduling
    
    /// Проверяет, нужно ли отправлять сообщение с задержкой
    public func shouldScheduleMessage() -> Bool {
        return currentSettings.ghostModeEnabled && currentSettings.useScheduledSend
    }
    
    /// Получает время задержки для отправки сообщения
    public func getScheduleDelay() -> Int32 {
        return currentSettings.scheduledSendDelay
    }
    
    /// Добавляет сообщение в очередь отложенной отправки
    public func scheduleMessage(
        _ message: EnqueueMessage,
        peerId: PeerId,
        sendAction: @escaping () -> Signal<Void, NoError>
    ) -> Signal<Void, NoError> {
        if !shouldScheduleMessage() {
            // Отправляем сразу, если функция отключена
            return sendAction()
        }
        
        let delay = getScheduleDelay()
        let scheduledTime = Date().timeIntervalSince1970 + Double(delay)
        
        let info = ScheduledMessageInfo(
            message: message,
            peerId: peerId,
            scheduledTime: scheduledTime,
            sendAction: sendAction
        )
        
        return Signal { [weak self] subscriber in
            guard let self = self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            
            self.scheduledMessages.append(info)
            self.updateTimer()
            
            // Возвращаем успех сразу (сообщение в очереди)
            subscriber.putNext(())
            subscriber.putCompletion()
            
            return ActionDisposable {
                // Можно добавить логику отмены
            }
        }
    }
    
    /// Обрабатывает очередь отложенных сообщений
    private func processScheduledMessages() {
        let now = Date().timeIntervalSince1970
        var messagesToSend: [ScheduledMessageInfo] = []
        
        // Находим сообщения, готовые к отправке
        scheduledMessages = scheduledMessages.filter { info in
            if info.scheduledTime <= now {
                messagesToSend.append(info)
                return false
            }
            return true
        }
        
        // Отправляем сообщения
        for info in messagesToSend {
            let _ = info.sendAction().start()
        }
        
        updateTimer()
    }
    
    /// Обновляет таймер проверки очереди
    private func updateTimer() {
        timer?.invalidate()
        timer = nil
        
        if scheduledMessages.isEmpty {
            return
        }
        
        // Находим ближайшее время отправки
        if let nextTime = scheduledMessages.map({ $0.scheduledTime }).min() {
            let now = Date().timeIntervalSince1970
            let delay = max(0, nextTime - now)
            
            timer = SwiftSignalKit.Timer(
                timeout: delay,
                repeat: false,
                completion: { [weak self] in
                    self?.processScheduledMessages()
                },
                queue: Queue.mainQueue()
            )
            timer?.start()
        }
    }
    
    // MARK: - Wrapper для отправки сообщений
    
    /// Обёртка для стандартной функции отправки сообщений
    public func wrapSendMessage(
        network: Network,
        postbox: Postbox,
        stateManager: AccountStateManager,
        message: EnqueueMessage,
        peerId: PeerId,
        originalSendAction: @escaping () -> Signal<MessageId?, NoError>
    ) -> Signal<MessageId?, NoError> {
        if !shouldScheduleMessage() {
            return originalSendAction()
        }
        
        // Добавляем сообщение в очередь
        let sendSignal = Signal<Void, NoError> { subscriber in
            let _ = originalSendAction().start(
                next: { _ in
                    subscriber.putNext(())
                },
                completed: {
                    subscriber.putCompletion()
                }
            )
            return EmptyDisposable
        }
        
        // Планируем отправку
        return scheduleMessage(message, peerId: peerId, sendAction: { sendSignal })
        |> map { _ -> MessageId? in
            // Возвращаем временный ID или nil
            return nil
        }
    }
    
    /// Получает количество сообщений в очереди
    public func getPendingMessagesCount() -> Int {
        return scheduledMessages.count
    }
    
    /// Получает информацию о сообщениях в очереди
    public func getPendingMessages() -> [ScheduledMessageInfo] {
        return scheduledMessages
    }
    
    /// Отменяет все отложенные сообщения
    public func cancelAllScheduled() {
        scheduledMessages.removeAll()
        timer?.invalidate()
        timer = nil
    }
    
    /// Отменяет конкретное отложенное сообщение
    public func cancelScheduled(peerId: PeerId) {
        scheduledMessages.removeAll { $0.peerId == peerId }
        updateTimer()
    }
}

// MARK: - Scheduled Message Info
public struct ScheduledMessageInfo {
    let message: EnqueueMessage
    let peerId: PeerId
    let scheduledTime: TimeInterval
    let sendAction: () -> Signal<Void, NoError>
}

// MARK: - Helper Extensions
extension AyuGramScheduledSender {
    /// Обновляет настройки
    func refreshSettings() {
        let _ = (settingsManager.getSettings()
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.currentSettings = settings
        })
    }
}
