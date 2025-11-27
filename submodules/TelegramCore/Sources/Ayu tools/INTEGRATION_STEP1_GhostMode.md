# Шаг 1: Интеграция Ghost Mode (Режим Призрака)

## 📁 Файлы для изменения

### 1. State/ManagedAccountPresence.swift

#### Что изменить:

**А) Добавить импорт в начало файла:**

```swift
import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

// ✅ ДОБАВИТЬ ЭТУ СТРОКУ:
private let ayuGhostMode = AyuGramGhostMode.shared
```

**Б) Изменить метод `updatePresence` в классе `AccountPresenceManagerImpl`:**

**БЫЛО (строки 45-68):**
```swift
private func updatePresence(_ isOnline: Bool) {
    let request: Signal<Api.Bool, MTRpcError>
    if isOnline {
        let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updatePresence(true)
        }, queue: self.queue)
        self.onlineTimer = timer
        timer.start()
        request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
    } else {
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
    }
    self.isPerformingUpdate.set(true)
    self.currentRequestDisposable.set((request
    |> `catch` { _ -> Signal<Api.Bool, NoError> in
        return .single(.boolFalse)
    }
    |> deliverOn(self.queue)).start(completed: { [weak self] in
        guard let strongSelf = self else {
            return
        }
        strongSelf.isPerformingUpdate.set(false)
    }))
}
```

**СТАЛО:**
```swift
private func updatePresence(_ isOnline: Bool) {
    // ✅ AYUGRAM: Проверка Ghost Mode
    if !ayuGhostMode.shouldSendOnlineStatus() {
        // Ghost Mode активен - не отправляем онлайн статус
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        self.isPerformingUpdate.set(false)
        return
    }
    
    let request: Signal<Api.Bool, MTRpcError>
    if isOnline {
        let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updatePresence(true)
        }, queue: self.queue)
        self.onlineTimer = timer
        timer.start()
        request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
    } else {
        self.onlineTimer?.invalidate()
        self.onlineTimer = nil
        request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
    }
    self.isPerformingUpdate.set(true)
    self.currentRequestDisposable.set((request
    |> `catch` { _ -> Signal<Api.Bool, NoError> in
        return .single(.boolFalse)
    }
    |> deliverOn(self.queue)).start(completed: { [weak self] in
        guard let strongSelf = self else {
            return
        }
        strongSelf.isPerformingUpdate.set(false)
    }))
}
```

---

### 2. State/ManagedLocalInputActivities.swift

#### Что изменить:

**А) Добавить импорт в начало файла:**

```swift
import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

// ✅ ДОБАВИТЬ ЭТУ СТРОКУ:
private let ayuGhostMode = AyuGramGhostMode.shared
```

**Б) Изменить функцию `requestActivity` (строки 102-178):**

Найдите строку:
```swift
private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {
```

**Добавьте проверку сразу после объявления функции:**

```swift
private func requestActivity(postbox: Postbox, network: Network, accountPeerId: PeerId, peerId: PeerId, threadId: Int64?, activity: PeerInputActivity?) -> Signal<Void, NoError> {
    // ✅ AYUGRAM: Проверка Ghost Mode для typing статуса
    if !ayuGhostMode.shouldSendTypingStatus() {
        // Ghost Mode активен - не отправляем typing статус
        return .complete()
    }
    
    return postbox.transaction { transaction -> Signal<Void, NoError> in
        // ... остальной код без изменений
```

---

### 3. State/SynchronizePeerReadState.swift

#### Что изменить:

**А) Добавить импорт в начало файла:**

```swift
import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit

// ✅ ДОБАВИТЬ ЭТУ СТРОКУ:
private let ayuGhostMode = AyuGramGhostMode.shared
```

**Б) Изменить функцию `pushPeerReadState` для каналов (строки 242-271):**

Найдите код:
```swift
case let .inputPeerChannel(channelId, accessHash):
    switch readState {
    case let .idBased(maxIncomingReadId, _, _, _, markedUnread):
        var pushSignal: Signal<Void, NoError> = network.request(Api.functions.channels.readHistory(channel: Api.InputChannel.inputChannel(channelId: channelId, accessHash: accessHash), maxId: maxIncomingReadId))
```

**Замените на:**
```swift
case let .inputPeerChannel(channelId, accessHash):
    switch readState {
    case let .idBased(maxIncomingReadId, _, _, _, markedUnread):
        // ✅ AYUGRAM: Проверка Ghost Mode для read receipts
        if !ayuGhostMode.shouldSendReadReceipt(for: peerId) {
            // Ghost Mode активен - не отправляем read receipts
            return .single(readState)
        }
        
        var pushSignal: Signal<Void, NoError> = network.request(Api.functions.channels.readHistory(channel: Api.InputChannel.inputChannel(channelId: channelId, accessHash: accessHash), maxId: maxIncomingReadId))
```

**В) Изменить функцию `pushPeerReadState` для обычных чатов (строки 272-310):**

Найдите код:
```swift
default:
    switch readState {
    case let .idBased(maxIncomingReadId, _, _, _, markedUnread):
        var pushSignal: Signal<Void, NoError> = network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: maxIncomingReadId))
```

**Замените на:**
```swift
default:
    switch readState {
    case let .idBased(maxIncomingReadId, _, _, _, markedUnread):
        // ✅ AYUGRAM: Проверка Ghost Mode для read receipts
        if !ayuGhostMode.shouldSendReadReceipt(for: peerId) {
            // Ghost Mode активен - не отправляем read receipts
            return .single(readState)
        }
        
        var pushSignal: Signal<Void, NoError> = network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: maxIncomingReadId))
```

---

### 4. State/ManagedSynchronizeConsumeMessageContentsOperations.swift

#### Что изменить:

**А) Добавить импорт в начало файла:**

```swift
import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

// ✅ ДОБАВИТЬ ЭТУ СТРОКУ:
private let ayuGhostMode = AyuGramGhostMode.shared
```

**Б) Изменить функцию `synchronizeConsumeMessageContents` (строки 81-122):**

Найдите начало функции:
```swift
private func synchronizeConsumeMessageContents(transaction: Transaction, network: Network, stateManager: AccountStateManager, peerId: PeerId, operation: SynchronizeConsumeMessageContentsOperation) -> Signal<Void, NoError> {
```

**Добавьте проверку сразу после объявления:**

```swift
private func synchronizeConsumeMessageContents(transaction: Transaction, network: Network, stateManager: AccountStateManager, peerId: PeerId, operation: SynchronizeConsumeMessageContentsOperation) -> Signal<Void, NoError> {
    // ✅ AYUGRAM: Проверка Ghost Mode для воспроизведения медиа
    // Определяем тип медиа по сообщениям
    var hasVoiceOrVideo = false
    for messageId in operation.messageIds {
        if let message = transaction.getMessage(messageId) {
            for media in message.media {
                if media is TelegramMediaFile {
                    hasVoiceOrVideo = true
                    break
                }
            }
        }
    }
    
    if hasVoiceOrVideo {
        if !ayuGhostMode.shouldSendVoicePlaybackStatus() {
            // Ghost Mode активен - не отправляем статус воспроизведения
            return .complete()
        }
    }
    
    if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
        // ... остальной код без изменений
```

---

## 🔧 Дополнительные изменения

### Обновить AyuGramGhostMode.swift

Добавить singleton для удобного доступа:

```swift
// В начало файла AyuGramGhostMode.swift добавить:
public final class AyuGramGhostMode {
    // ✅ Singleton для глобального доступа
    public static let shared = AyuGramGhostMode(
        settingsManager: AyuGramSettingsManager.shared
    )
    
    // ... остальной код
}

// И в AyuGramSettings.swift:
public final class AyuGramSettingsManager {
    // ✅ Singleton для глобального доступа
    public static let shared: AyuGramSettingsManager = {
        // Получить accountManager из глобального контекста
        // Это нужно будет настроить при инициализации приложения
        fatalError("AyuGramSettingsManager.shared must be initialized at app startup")
    }()
    
    // ... остальной код
}
```

---

## ✅ Проверка

После внесения изменений проверьте:

1. **Компиляция**: Проект должен компилироваться без ошибок
2. **Ghost Mode выключен**: Всё работает как раньше
3. **Ghost Mode включен**: 
   - Онлайн статус не отправляется
   - Read receipts не отправляются
   - Typing статус не отправляется
   - Статус просмотра медиа не отправляется

---

## 📝 Примечания

1. Все изменения минимальны и не ломают существующий код
2. Если Ghost Mode выключен, всё работает как обычно
3. Код изолирован и легко откатывается
4. Используется singleton паттерн для удобного доступа

---

## ⚠️ Важно

Перед использованием нужно:
1. Инициализировать `AyuGramSettingsManager.shared` при запуске приложения
2. Передать правильный `accountManager`
3. Убедиться что все файлы из папки `ayu/` добавлены в проект
