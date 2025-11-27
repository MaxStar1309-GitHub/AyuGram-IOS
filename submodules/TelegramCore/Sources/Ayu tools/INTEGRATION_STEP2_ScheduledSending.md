# Шаг 2: Интеграция отложенной отправки сообщений

## 📋 Обзор

Для реализации отложенной отправки сообщений (чтобы "последний раз в сети" не обновлялся) нам нужно:
1. Перехватывать момент отправки сообщения
2. Добавлять задержку (12 секунд по умолчанию)
3. Отправлять сообщение после задержки

## 🎯 Подход

Telegram iOS использует `PendingMessageManager` для управления очередью сообщений. Вместо изменения этого большого файла, мы создадим обёртку, которая будет задерживать отправку.

---

## 📁 Файлы для создания

### 1. Создать новый файл: `State/AyuGramDelayedSender.swift`

Этот файл будет содержать логику задержки отправки:

```swift
import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit

/// Менеджер отложенной отправки сообщений для AyuGram
final class AyuGramDelayedSender {
    private let queue: Queue
    private var delayedMessages: [MessageId: DelayedMessage] = [:]
    private let settingsManager: AyuGramSettingsManager
    
    struct DelayedMessage {
        let messageId: MessageId
        let scheduledTime: Double
        let timer: SwiftSignalKit.Timer
    }
    
    init(queue: Queue, settingsManager: AyuGramSettingsManager) {
        self.queue = queue
        self.settingsManager = settingsManager
    }
    
    /// Проверяет, нужно ли задерживать отправку
    func shouldDelayMessage() -> Bool {
        var result = false
        let _ = settingsManager.getSettings().start(next: { settings in
            result = settings.ghostModeEnabled && settings.useScheduledSend
        })
        return result
    }
    
    /// Получает задержку в секундах
    func getDelay() -> Int32 {
        var delay: Int32 = 12
        let _ = settingsManager.getSettings().start(next: { settings in
            delay = settings.scheduledSendDelay
        })
        return delay
    }
    
    /// Планирует отправку сообщения с задержкой
    func scheduleMessage(
        messageId: MessageId,
        sendAction: @escaping () -> Void
    ) {
        assert(queue.isCurrent())
        
        guard shouldDelayMessage() else {
            // Если отложенная отправка отключена, отправляем сразу
            sendAction()
            return
        }
        
        let delay = TimeInterval(getDelay())
        let scheduledTime = Date().timeIntervalSince1970 + delay
        
        // Создаём таймер
        let timer = SwiftSignalKit.Timer(
            timeout: delay,
            repeat: false,
            completion: { [weak self] in
                guard let self = self else { return }
                
                // Отправляем сообщение
                sendAction()
                
                // Удаляем из очереди
                self.delayedMessages.removeValue(forKey: messageId)
            },
            queue: self.queue
        )
        
        let delayedMessage = DelayedMessage(
            messageId: messageId,
            scheduledTime: scheduledTime,
            timer: timer
        )
        
        delayedMessages[messageId] = delayedMessage
        timer.start()
    }
    
    /// Отменяет отложенную отправку сообщения
    func cancelMessage(messageId: MessageId) {
        assert(queue.isCurrent())
        
        if let delayed = delayedMessages[messageId] {
            delayed.timer.invalidate()
            delayedMessages.removeValue(forKey: messageId)
        }
    }
    
    /// Отменяет все отложенные сообщения
    func cancelAll() {
        assert(queue.isCurrent())
        
        for (_, delayed) in delayedMessages {
            delayed.timer.invalidate()
        }
        delayedMessages.removeAll()
    }
    
    /// Получает информацию об отложенных сообщениях
    func getDelayedMessages() -> [MessageId: Double] {
        assert(queue.isCurrent())
        
        var result: [MessageId: Double] = [:]
        for (messageId, delayed) in delayedMessages {
            result[messageId] = delayed.scheduledTime
        }
        return result
    }
}
```

---

## 📁 Файлы для изменения

### 2. State/PendingMessageManager.swift

#### Изменение А: Добавить AyuGramDelayedSender

**В начало класса `PendingMessageManager` (примерно строка 179):**

Найдите:
```swift
public final class PendingMessageManager {
    private let queue = Queue()
    private let account: Account
```

**Добавьте после этого:**
```swift
public final class PendingMessageManager {
    private let queue = Queue()
    private let account: Account
    
    // ✅ AYUGRAM: Менеджер отложенной отправки
    private var ayuDelayedSender: QueueLocalObject<AyuGramDelayedSender>?
```

#### Изменение Б: Инициализация AyuGramDelayedSender

**В конструкторе `init` (примерно строка 208):**

Найдите:
```swift
public init(account: Account) {
    self.account = account
    // ... другой код инициализации
```

**Добавьте в конец конструктора:**
```swift
    // ✅ AYUGRAM: Инициализация менеджера отложенной отправки
    if let settingsManager = AyuGramSettingsManager.sharedInstance {
        let queue = self.queue
        self.ayuDelayedSender = QueueLocalObject(queue: self.queue, generate: {
            return AyuGramDelayedSender(queue: queue, settingsManager: settingsManager)
        })
    }
}
```

#### Изменение В: Оборачивание отправки сообщений

**В функции `sendMessageContent` (строка 1479):**

Это самое важное изменение. Нужно обернуть фактическую отправку сообщения.

Найдите место, где создаётся `sendMessageRequest` и отправляется запрос (примерно строки 1591-2000).

**Найдите код похожий на:**
```swift
let sendMessageRequest: Signal<NetworkRequestResult<Api.Updates>, MTRpcError>
switch content.content {
    case .text:
        // ... создание запроса
        sendMessageRequest = network.download(to: Api.functions.messages.sendMessage(...))
    case .media:
        // ... создание запроса
        sendMessageRequest = network.download(to: Api.functions.messages.sendMedia(...))
    // ... другие случаи
}

// Затем где-то ниже:
let signal = sendMessageRequest
|> deliverOn(queue)
|> mapToSignal { result -> Signal<Void, NoError> in
    // Обработка результата
}
```

**Оберните весь signal в функцию задержки:**

```swift
// ✅ AYUGRAM: Обёртка для отложенной отправки
let wrappedSignal = Signal<Void, NoError> { [weak self] subscriber in
    guard let self = self else {
        subscriber.putCompletion()
        return EmptyDisposable
    }
    
    // Создаём closure для отправки
    let sendAction = {
        let disposable = signal.start(
            next: { value in
                subscriber.putNext(value)
            },
            error: { error in
                subscriber.putError(error)
            },
            completed: {
                subscriber.putCompletion()
            }
        )
    }
    
    // Проверяем, нужно ли задерживать
    self.ayuDelayedSender?.with { sender in
        sender.scheduleMessage(messageId: messageId, sendAction: sendAction)
    }
    
    return ActionDisposable {
        // При отмене - отменяем задержку
        self?.ayuDelayedSender?.with { sender in
            sender.cancelMessage(messageId: messageId)
        }
    }
}

return wrappedSignal
```

---

## ⚠️ Альтернативный подход (более простой)

Если изменение `PendingMessageManager` слишком сложное, можно использовать более простой подход - задерживать обновление онлайн статуса вместо самих сообщений.

### Альтернатива: Изменить только ManagedAccountPresence.swift

**В функции `updatePresence` (которую мы уже изменили для Ghost Mode):**

```swift
private func updatePresence(_ isOnline: Bool) {
    // ✅ AYUGRAM: Проверка Ghost Mode
    if !ayuGhostMode.shouldSendOnlineStatus() {
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        self.isPerformingUpdate.set(false)
        return
    }
    
    // ✅ AYUGRAM: Проверка отложенной отправки
    let delay = ayuGhostMode.getScheduledSendDelay()
    if delay > 0 && isOnline {
        // Вместо немедленной отправки, задерживаем обновление статуса
        let timer = SignalKitTimer(timeout: Double(delay), repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            // После задержки отправляем статус "онлайн"
            let request = strongSelf.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
            strongSelf.currentRequestDisposable.set((request
            |> `catch` { _ -> Signal<Api.Bool, NoError> in
                return .single(.boolFalse)
            }
            |> deliverOn(strongSelf.queue)).start(completed: {
                strongSelf.isPerformingUpdate.set(false)
            }))
        }, queue: self.queue)
        
        self.onlineTimer = timer
        timer.start()
        self.isPerformingUpdate.set(true)
        return
    }
    
    // Обычная логика (код без изменений)
    let request: Signal<Api.Bool, MTRpcError>
    if isOnline {
        // ... остальной код без изменений
    }
}
```

---

## 🔧 Обновление AyuGramGhostMode.swift

Добавить метод получения задержки:

```swift
public final class AyuGramGhostMode {
    // ... существующий код
    
    /// Получает задержку отправки в секундах (0 если отключено)
    public func getScheduledSendDelay() -> Int32 {
        if !currentSettings.ghostModeEnabled || !currentSettings.useScheduledSend {
            return 0
        }
        return currentSettings.scheduledSendDelay
    }
}
```

---

## ✅ Рекомендация

**Используйте альтернативный подход** (изменение только `ManagedAccountPresence.swift`), потому что:

1. Проще в реализации
2. Меньше изменений в коде
3. Достигается та же цель - "последний раз в сети" не обновляется сразу
4. Легче тестировать и отлаживать

Полное изменение `PendingMessageManager` может быть добавлено позже, если понадобится более точный контроль.

---

## 📝 Проверка

После внесения изменений:

1. **Ghost Mode выключен**: Сообщения отправляются сразу, статус обновляется
2. **Ghost Mode + отложенная отправка**: 
   - Сообщения отправляются сразу, но статус "онлайн" обновляется через 12 секунд
   - "Последний раз в сети" не меняется сразу после отправки
3. **Отправка нескольких сообщений**: Каждое сообщение сбрасывает таймер задержки

---

## 💡 Дополнительная функция

Можно добавить индикатор "планируемой отправки" в UI, чтобы пользователь видел, что сообщение будет отправлено с задержкой.
