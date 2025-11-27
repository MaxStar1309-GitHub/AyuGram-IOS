# AyuGram для iOS - Инструкция по интеграции

## 🚀 Быстрый старт

1. **Скопируйте папку `ayu/`** в `TelegramCore/Sources/`
2. **Следуйте инструкциям** в файлах INTEGRATION_STEP*.md по порядку
3. **Читайте SETUP_GUIDE.md** для полной настройки

## 📚 Документация

- **[SETUP_GUIDE.md](../SETUP_GUIDE.md)** - Полная инструкция по настройке и инициализации
- **[INTEGRATION_STEP1_GhostMode.md](INTEGRATION_STEP1_GhostMode.md)** - Интеграция Режима Призрака
- **[INTEGRATION_STEP2_ScheduledSending.md](INTEGRATION_STEP2_ScheduledSending.md)** - Интеграция отложенной отправки
- **[INTEGRATION_STEP3_MessageHistory.md](INTEGRATION_STEP3_MessageHistory.md)** - Сохранение удалённых/изменённых
- **[FILE_SEARCH_GUIDE.md](../FILE_SEARCH_GUIDE.md)** - Руководство по поиску файлов
- **[OVERVIEW.md](../OVERVIEW.md)** - Общий обзор проекта

---

## Структура проекта

Все файлы AyuGram находятся в папке `TelegramCore/Sources/ayu/`:

```
TelegramCore/Sources/ayu/
├── AyuGramSettings.swift          # Настройки AyuGram и менеджер настроек
├── AyuGramGhostMode.swift         # Логика Режима Призрака
├── AyuGramMessageHistory.swift    # Сохранение удалённых/изменённых сообщений
└── AyuGramScheduledSender.swift   # Отложенная отправка сообщений
```

## Шаг 1: Создание папки и копирование файлов

1. Создайте папку `ayu` в `TelegramCore/Sources/`
2. Скопируйте все 4 файла в эту папку
3. Добавьте файлы в Xcode проект (если требуется)

## Шаг 2: Интеграция с основным кодом

### 2.1 Инициализация AyuGram

В файле, где инициализируется `AccountManager` (обычно это `AccountContext` или подобный), добавьте:

```swift
import ayu // Или полный путь: import TelegramCore.ayu

// В классе AccountContext или где хранится контекст приложения
private let ayuSettingsManager: AyuGramSettingsManager
private let ayuGhostMode: AyuGramGhostMode
private let ayuScheduledSender: AyuGramScheduledSender
private let ayuMessageHistory: AyuGramMessageHistory

// В init():
self.ayuSettingsManager = AyuGramSettingsManager(accountManager: accountManager)
self.ayuGhostMode = AyuGramGhostMode(settingsManager: ayuSettingsManager)
self.ayuScheduledSender = AyuGramScheduledSender(settingsManager: ayuSettingsManager)
self.ayuMessageHistory = AyuGramMessageHistory(
    settingsManager: ayuSettingsManager,
    postbox: account.postbox
)
```

### 2.2 Интеграция Режима Призрака

Найдите файлы, отвечающие за:
- Отправку онлайн статуса
- Отправку read receipts (прочтение сообщений)
- Отправку typing status (печатает)
- Воспроизведение голосовых сообщений
- Просмотр видео

**Примерные имена файлов для поиска:**
- `UpdateStatus.swift` или файл с `updateStatus`
- `ReadHistory.swift` или файл с `readMessageHistory`
- `SetTyping.swift` или файл с `setTyping`

**Что нужно изменить:**

#### Пример 1: Отправка онлайн статуса
```swift
// БЫЛО:
func updateOnlineStatus() {
    // Отправка статуса на сервер
}

// СТАЛО:
func updateOnlineStatus() {
    guard ayuGhostMode.shouldSendOnlineStatus() else {
        return // Не отправляем в режиме призрака
    }
    // Отправка статуса на сервер
}
```

#### Пример 2: Прочтение сообщений
```swift
// БЫЛО:
func readMessages(messageIds: [MessageId], peerId: PeerId) -> Signal<Void, NoError> {
    // Стандартная логика чтения
}

// СТАЛО:
func readMessages(messageIds: [MessageId], peerId: PeerId) -> Signal<Void, NoError> {
    return ayuGhostMode.readMessages(
        network: network,
        postbox: postbox,
        stateManager: stateManager,
        peerId: peerId,
        messageIds: messageIds
    )
}
```

#### Пример 3: Typing статус
```swift
// БЫЛО:
func sendTyping(peerId: PeerId) {
    // Отправка статуса "печатает"
}

// СТАЛО:
func sendTyping(peerId: PeerId) {
    guard ayuGhostMode.shouldSendTypingStatus() else {
        return // Не отправляем в режиме призрака
    }
    // Отправка статуса "печатает"
}
```

### 2.3 Интеграция отложенной отправки

Найдите функцию отправки сообщений (обычно `enqueueMessage` или `sendMessage`):

```swift
// БЫЛО:
func sendMessage(_ message: EnqueueMessage, peerId: PeerId) -> Signal<MessageId?, NoError> {
    // Стандартная отправка
}

// СТАЛО:
func sendMessage(_ message: EnqueueMessage, peerId: PeerId) -> Signal<MessageId?, NoError> {
    return ayuScheduledSender.wrapSendMessage(
        network: network,
        postbox: postbox,
        stateManager: stateManager,
        message: message,
        peerId: peerId,
        originalSendAction: {
            // Оригинальная логика отправки
        }
    )
}
```

### 2.4 Интеграция сохранения удалённых сообщений

Найдите обработчик удаления сообщений (обычно в файле с `deleteMessages` или при получении update о удалении):

```swift
// При получении уведомления об удалении сообщения:
func handleDeletedMessages(_ messages: [Message]) {
    let deletedAt = Int32(Date().timeIntervalSince1970)
    
    // Сохраняем в AyuGram
    let _ = ayuMessageHistory.saveDeletedMessages(messages, deletedAt: deletedAt).start()
    
    // Стандартная логика удаления
}
```

### 2.5 Интеграция сохранения изменённых сообщений

Найдите обработчик изменения сообщений:

```swift
// При получении уведомления об изменении сообщения:
func handleEditedMessage(original: Message, edited: Message) {
    let editedAt = Int32(Date().timeIntervalSince1970)
    
    // Сохраняем в AyuGram
    let _ = ayuMessageHistory.saveEditedMessage(
        originalMessage: original,
        editedMessage: edited,
        editedAt: editedAt
    ).start()
    
    // Стандартная логика обновления
}
```

## Шаг 3: Создание UI для настроек

Нужно добавить экран настроек AyuGram в меню настроек Telegram.

### 3.1 Добавить пункт в главное меню настроек

Найдите файл с настройками (обычно `SettingsController.swift` или подобный):

```swift
// Добавить новый элемент в список:
.item(
    title: "AyuGram",
    icon: .ayugram, // Или использовать стандартную иконку
    action: {
        // Открыть экран настроек AyuGram
        let controller = AyuGramSettingsController(
            context: context,
            settingsManager: ayuSettingsManager
        )
        navigationController?.pushViewController(controller)
    }
)
```

### 3.2 Создать экран настроек AyuGram

Создайте новый файл `AyuGramSettingsController.swift` в папке с UI:

```swift
import UIKit
import Display
import SwiftSignalKit

class AyuGramSettingsController: ViewController {
    private let context: AccountContext
    private let settingsManager: AyuGramSettingsManager
    private var settings: AyuGramSettings = .default
    
    init(context: AccountContext, settingsManager: AyuGramSettingsManager) {
        self.context = context
        self.settingsManager = settingsManager
        super.init(navigationBarPresentationData: nil)
        
        self.title = "AyuGram"
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Загрузить настройки
        let _ = (settingsManager.getSettings()
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.settings = settings
            self?.updateUI()
        })
    }
    
    private func updateUI() {
        // Создать UI с переключателями для:
        // 1. Режим Призрака (включить/выключить)
        // 2. Отложенная отправка (включить/выключить, настроить задержку)
        // 3. Сохранение удалённых сообщений (включить/выключить)
        // 4. Сохранение изменённых сообщений (включить/выключить)
    }
}
```

## Шаг 4: Файлы для поиска и изменения

Вам нужно будет найти и изменить следующие файлы в `TelegramCore/Sources/`:

1. **Для онлайн статуса:**
   - Ищите файлы с `UpdateStatus`, `updateOnlineStatus`, или `setOnline`
   - Вероятные места: `Network/`, `Account/`, `Api/`

2. **Для read receipts:**
   - Ищите `readMessageHistory`, `ReadHistory`, `messages.readHistory`
   - Вероятные места: `Messages/`, `Network/`, `SyncCore/`

3. **Для typing статус:**
   - Ищите `setTyping`, `SendTyping`, `messages.setTyping`
   - Вероятные места: `Messages/`, `Network/`

4. **Для отправки сообщений:**
   - Ищите `enqueueMessage`, `sendMessage`, `SendMessage`
   - Вероятные места: `Messages/`, `MessageSending/`

5. **Для обработки удалений:**
   - Ищите `deleteMessages`, `DeleteMessages`, `handleDeletedMessages`
   - Вероятные места: `Messages/`, `Updates/`

6. **Для обработки изменений:**
   - Ищите `editMessage`, `EditMessage`, `handleEditedMessage`
   - Вероятные места: `Messages/`, `Updates/`

## Шаг 5: Тестирование

1. **Режим Призрака:**
   - Включите режим призрака
   - Откройте чат
   - Проверьте, что статус "онлайн" не отображается у собеседника
   - Прочитайте сообщения и проверьте, что галочки не становятся синими

2. **Отложенная отправка:**
   - Включите отложенную отправку
   - Отправьте сообщение
   - Проверьте, что оно отправится через указанное время
   - Проверьте, что статус "последний раз в сети" не обновляется

3. **Сохранение удалённых:**
   - Включите сохранение удалённых
   - Попросите кого-то отправить и удалить сообщение
   - Проверьте, что сообщение осталось с пометкой "удалено"

4. **Сохранение изменённых:**
   - Включите сохранение изменённых
   - Попросите кого-то изменить сообщение
   - Откройте историю изменений
   - Проверьте, что все версии сохранились

## Следующие шаги

После базовой интеграции нужно будет:

1. Доработать UI для настроек
2. Добавить отображение удалённых сообщений в чате
3. Добавить просмотр истории изменений
4. Реализовать пересылку из приватных групп (пункт 5)
5. Реализовать перехват исчезающих сообщений (пункт 6)

## Примечания

- Все файлы используют стандартные типы из TelegramCore
- Минимальные изменения в существующий код
- Вся логика изолирована в папке `ayu/`
- Легко включать/выключать функции через настройки

## Нужна помощь?

Если вам нужно увидеть конкретные файлы из проекта, предоставьте их содержимое, и я помогу с интеграцией.
