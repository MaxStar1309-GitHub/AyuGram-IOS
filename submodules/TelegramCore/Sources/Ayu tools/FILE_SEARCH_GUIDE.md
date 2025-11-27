# Руководство по поиску файлов для интеграции AyuGram

## 🎯 Что мы ищем

### 1. Онлайн статус (Online Status)
**Ключевые слова для поиска:**
- `updateStatus`
- `UpdateUserStatus`
- `setOnline`
- `userPresence`
- `AccountPresenceManager`
- `presence`

**Вероятные файлы:**
- `State/AccountPresenceManager.swift`
- `State/AccountStateManager.swift`
- `Network/UpdateStatus.swift`
- Любой файл с "Presence" в названии

**Что нужно найти:**
```swift
// Функция, которая отправляет статус "онлайн" на сервер
func updateUserStatus() {
    // Здесь отправляется запрос типа account.updateStatus
}
```

---

### 2. Read Receipts (Прочтение сообщений)
**Ключевые слова для поиска:**
- `readHistory`
- `readMessageHistory`
- `messages.readHistory`
- `markAsRead`
- `readContents`

**Вероятные файлы:**
- `State/ReadHistory.swift`
- `Account/ReadHistory.swift`
- `PendingMessages/ReadHistory.swift`
- Файлы в папке `TelegramEngine/Messages/`

**Что нужно найти:**
```swift
// Функция, которая отправляет подтверждение прочтения
func readMessageHistory(peerId: PeerId, messageIds: [MessageId]) {
    // Здесь отправляется запрос messages.readHistory
}
```

---

### 3. Typing Status (Печатает)
**Ключевые слова для поиска:**
- `setTyping`
- `sendTyping`
- `messages.setTyping`
- `SendMessageTypingAction`

**Вероятные файлы:**
- `State/SendTyping.swift`
- `Account/SendTyping.swift`
- Файлы в `TelegramEngine/Messages/`

**Что нужно найти:**
```swift
// Функция, которая отправляет статус "печатает"
func setTyping(peerId: PeerId, action: SendMessageTypingAction) {
    // Здесь отправляется запрос messages.setTyping
}
```

---

### 4. Отправка сообщений (Message Sending)
**Ключевые слова для поиска:**
- `enqueueMessage`
- `sendMessage`
- `EnqueueMessage`
- `PendingMessageManager`

**Вероятные файлы:**
- `PendingMessages/PendingMessageManager.swift`
- `Account/EnqueueMessage.swift`
- Файлы в `TelegramEngine/Messages/`

**Что нужно найти:**
```swift
// Функция, которая ставит сообщение в очередь на отправку
func enqueueMessage(_ message: EnqueueMessage) -> Signal<MessageId?, NoError> {
    // Логика постановки в очередь и отправки
}
```

---

### 5. Обработка Updates (Удаления и изменения)
**Ключевые слова для поиска:**
- `processUpdate`
- `handleUpdate`
- `UpdateMessageID`
- `deleteMessages`
- `editMessage`

**Вероятные файлы:**
- `State/AccountStateManager.swift`
- `State/ManagedAccountStateUpdates.swift`
- Любые файлы с "Update" в названии

**Что нужно найти:**
```swift
// Обработчик удаления сообщений
case .updateDeleteMessages(let messages):
    // Логика обработки удаления

// Обработчик изменения сообщений
case .updateEditMessage(let message):
    // Логика обработки изменения
```

---

### 6. Воспроизведение медиа
**Ключевые слова для поиска:**
- `markContentAsConsumed`
- `messages.readMessageContents`
- `openMediaMessage`
- `consumeMessage`

**Вероятные файлы:**
- Файлы в `TelegramEngine/Messages/`
- `Account/ConsumedMessageContents.swift`

**Что нужно найти:**
```swift
// Функция, вызываемая при воспроизведении голосовых/видео
func markAsConsumed(messageIds: [MessageId]) {
    // Отправка подтверждения просмотра/прослушивания
}
```

---

## 📋 Приоритет поиска

### Первая очередь (для Режима Призрака):
1. ✅ **Онлайн статус** - State/AccountPresenceManager.swift
2. ✅ **Read Receipts** - Файлы с readHistory
3. ✅ **Typing статус** - Файлы с setTyping

### Вторая очередь (для отложенной отправки):
4. ✅ **Отправка сообщений** - PendingMessages/

### Третья очередь (для истории):
5. ✅ **Обработка updates** - State/AccountStateManager.swift
6. ✅ **Удаления** - обработчик updateDeleteMessages
7. ✅ **Изменения** - обработчик updateEditMessage

---

## 🔍 Команды для поиска (Windows)

```cmd
# Поиск по содержимому файлов
findstr /s /i "updateStatus" *.swift
findstr /s /i "readHistory" *.swift
findstr /s /i "setTyping" *.swift
findstr /s /i "enqueueMessage" *.swift
findstr /s /i "deleteMessages" *.swift
```

## 🔍 Команды для поиска (Mac/Linux)

```bash
# Поиск по содержимому файлов
grep -r -i "updateStatus" *.swift
grep -r -i "readHistory" *.swift
grep -r -i "setTyping" *.swift
grep -r -i "enqueueMessage" *.swift
grep -r -i "deleteMessages" *.swift
```

---

## 📁 Структура которую нужно показать

Пожалуйста, покажите:

### 1. Список файлов из State/
```
dir State /b
```

### 2. Список файлов из Account/
```
dir Account /b
```

### 3. Список файлов из Network/
```
dir Network /b
```

### 4. Список файлов из PendingMessages/
```
dir PendingMessages /b
```

### 5. Если есть TelegramEngine/Messages/
```
dir TelegramEngine\Messages /b
```

---

## 🎯 Что делать дальше

1. **Покажите списки файлов** из указанных папок
2. **Я определю нужные файлы** для каждой функции
3. **Вы покажете содержимое** конкретных файлов
4. **Я создам точные изменения** для интеграции

---

## 💡 Подсказки

- Файлы обычно названы по их функциональности
- `AccountPresenceManager` = управление онлайн статусом
- `ReadHistory` = прочтение истории сообщений
- `PendingMessageManager` = отправка сообщений
- `AccountStateManager` = обработка всех updates от Telegram

Как только увижу списки файлов, смогу точно сказать, что нужно изменить! 🚀
