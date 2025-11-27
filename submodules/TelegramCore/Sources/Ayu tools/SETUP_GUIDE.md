# Полная инструкция по интеграции AyuGram в Telegram iOS

## 📦 Установка

### Шаг 1: Добавление файлов в проект

1. Скопируйте папку `ayu/` в `TelegramCore/Sources/`:
   ```
   TelegramCore/Sources/ayu/
   ├── AyuGramSettings.swift
   ├── AyuGramGhostMode.swift
   ├── AyuGramScheduledSender.swift
   └── AyuGramMessageHistory.swift
   ```

2. Добавьте файлы в Xcode проект (если требуется)

---

## 🔧 Инициализация

### Шаг 2: Настройка в Account.swift или главном файле инициализации

Найдите файл где создаётся `Account` (обычно `Account/Account.swift` или файл инициализации приложения).

**Добавьте инициализацию AyuGram:**

```swift
import Foundation
// ... другие импорты

// В файле Account.swift или где инициализируется приложение

public final class Account {
    // ... существующие поля
    
    // ✅ AYUGRAM: Добавить поля
    public let ayuSettingsManager: AyuGramSettingsManager
    public let ayuGhostMode: AyuGramGhostMode
    public let ayuScheduledSender: AyuGramScheduledSender
    public let ayuMessageHistory: AyuGramMessageHistory
    
    public init(
        id: AccountRecordId,
        basePath: String,
        testingEnvironment: Bool,
        postbox: Postbox,
        network: Network,
        peerId: PeerId,
        // ... другие параметры
    ) {
        // ... существующая инициализация
        
        // ✅ AYUGRAM: Инициализация менеджеров
        self.ayuSettingsManager = AyuGramSettingsManager(accountManager: accountManager)
        self.ayuGhostMode = AyuGramGhostMode(settingsManager: self.ayuSettingsManager)
        self.ayuScheduledSender = AyuGramScheduledSender(settingsManager: self.ayuSettingsManager)
        self.ayuMessageHistory = AyuGramMessageHistory(
            settingsManager: self.ayuSettingsManager,
            postbox: postbox
        )
        
        // ... остальная инициализация
    }
}
```

### Шаг 3: Обновить AyuGramGhostMode для использования через Account

В `AyuGramGhostMode.swift` **УДАЛИТЕ** строку:
```swift
private let ayuGhostMode = AyuGramGhostMode.shared  // ❌ УДАЛИТЬ
```

И вместо этого получайте экземпляр через Account.

---

## 🔌 Передача экземпляров в нужные места

### Шаг 4: Передать AyuGram в ManagedAccountPresence

**В файле State/ManagedAccountPresence.swift:**

```swift
// Изменить сигнатуру init
final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    // ✅ Добавить параметр
    init(
        shouldKeepOnlinePresence: Signal<Bool, NoError>,
        network: Network,
        ayuGhostMode: AyuGramGhostMode  // Новый параметр
    ) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(
                queue: queue,
                shouldKeepOnlinePresence: shouldKeepOnlinePresence,
                network: network,
                ayuGhostMode: ayuGhostMode  // Передаём дальше
            )
        })
    }
}

// И в AccountPresenceManagerImpl
private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let ayuGhostMode: AyuGramGhostMode  // ✅ Добавить поле
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    init(
        queue: Queue,
        shouldKeepOnlinePresence: Signal<Bool, NoError>,
        network: Network,
        ayuGhostMode: AyuGramGhostMode  // ✅ Новый параметр
    ) {
        self.queue = queue
        self.network = network
        self.ayuGhostMode = ayuGhostMode  // ✅ Сохранить
        
        // ... остальной код
    }
    
    private func updatePresence(_ isOnline: Bool) {
        // ✅ Теперь используем self.ayuGhostMode вместо глобального
        if !self.ayuGhostMode.shouldSendOnlineStatus() {
            // Ghost Mode активен
            return
        }
        
        // ... остальной код
    }
}
```

**Где создаётся AccountPresenceManager:**

Найдите место где вызывается `AccountPresenceManager(...)` и добавьте параметр:

```swift
// Было:
let presenceManager = AccountPresenceManager(
    shouldKeepOnlinePresence: ...,
    network: network
)

// Стало:
let presenceManager = AccountPresenceManager(
    shouldKeepOnlinePresence: ...,
    network: network,
    ayuGhostMode: account.ayuGhostMode  // ✅ Добавить
)
```

### Шаг 5: Аналогично для других файлов

**Для ManagedLocalInputActivities.swift:**

```swift
// Добавить параметр ayuGhostMode в функцию managedLocalTypingActivities
func managedLocalTypingActivities(
    activities: Signal<[PeerActivitySpace: [(PeerId, PeerInputActivityRecord)]], NoError>,
    postbox: Postbox,
    network: Network,
    accountPeerId: PeerId,
    ayuGhostMode: AyuGramGhostMode  // ✅ Добавить
) -> Signal<Void, NoError> {
    // ... и использовать его внутри
}
```

**Для SynchronizePeerReadState.swift:**

```swift
// Добавить параметр в функции push/validate
private func pushPeerReadState(
    network: Network,
    postbox: Postbox,
    stateManager: AccountStateManager,
    peerId: PeerId,
    ayuGhostMode: AyuGramGhostMode  // ✅ Добавить
) -> Signal<Never, PeerReadStateValidationError> {
    // ... использовать ayuGhostMode внутри
}
```

---

## 🎨 Создание UI для настроек

### Шаг 6: Добавить пункт в главное меню настроек

Найдите файл с настройками (примерно `Settings/SettingsController.swift`):

```swift
// В списке пунктов меню добавить:
let ayugramItem = ItemListDisclosureItem(
    presentationData: ItemListPresentationData(theme: presentationData.theme, fontSize: presentationData.fontSize, strings: presentationData.strings),
    title: "AyuGram",
    label: "",
    sectionId: self.section,
    style: .generic,
    action: {
        // Открыть экран настроек AyuGram
        let controller = AyuGramSettingsController(
            context: context,
            ayuSettingsManager: context.account.ayuSettingsManager
        )
        arguments.pushController(controller)
    }
)
```

### Шаг 7: Создать экран настроек AyuGram

Создайте файл `Settings/AyuGramSettingsController.swift`:

```swift
import Foundation
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

public func ayuGramSettingsController(
    context: AccountContext
) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    
    let settingsManager = context.account.ayuSettingsManager
    
    var updateSettingsImpl: ((AyuGramSettings) -> Void)?
    
    let signal = combineLatest(
        queue: .mainQueue(),
        settingsManager.getSettings()
    )
    |> map { settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("AyuGram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        
        var items: [ItemListItem] = []
        let section = ItemListSectionId(0)
        
        // 1. Ghost Mode
        items.append(ItemListSwitchItem(
            presentationData: ItemListPresentationData(presentationData),
            title: "👻 Режим Призрака",
            value: settings.ghostModeEnabled,
            sectionId: section,
            style: .blocks,
            updated: { value in
                var updatedSettings = settings
                updatedSettings.ghostModeEnabled = value
                updateSettingsImpl?(updatedSettings)
            }
        ))
        
        // 2. Отложенная отправка
        items.append(ItemListSwitchItem(
            presentationData: ItemListPresentationData(presentationData),
            title: "⏰ Отложенная отправка",
            value: settings.useScheduledSend,
            sectionId: section,
            style: .blocks,
            enabled: settings.ghostModeEnabled,
            updated: { value in
                var updatedSettings = settings
                updatedSettings.useScheduledSend = value
                updateSettingsImpl?(updatedSettings)
            }
        ))
        
        // 3. Сохранение удалённых
        items.append(ItemListSwitchItem(
            presentationData: ItemListPresentationData(presentationData),
            title: "🗑️ Сохранять удалённые",
            value: settings.saveDeletedMessages,
            sectionId: section,
            style: .blocks,
            updated: { value in
                var updatedSettings = settings
                updatedSettings.saveDeletedMessages = value
                updateSettingsImpl?(updatedSettings)
            }
        ))
        
        // 4. Сохранение изменённых
        items.append(ItemListSwitchItem(
            presentationData: ItemListPresentationData(presentationData),
            title: "✏️ Сохранять изменения",
            value: settings.saveEditedMessages,
            sectionId: section,
            style: .blocks,
            updated: { value in
                var updatedSettings = settings
                updatedSettings.saveEditedMessages = value
                updateSettingsImpl?(updatedSettings)
            }
        ))
        
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: items,
            style: .blocks
        )
        
        return (controllerState, (listState, nil))
    }
    
    let controller = ItemListController(
        context: context,
        state: signal
    )
    
    updateSettingsImpl = { [weak controller] settings in
        let _ = settingsManager.updateSettings(settings).start()
    }
    
    return controller
}
```

---

## ✅ Проверка интеграции

### Шаг 8: Тестирование

1. **Компиляция:**
   ```bash
   # Убедитесь что проект компилируется
   xcodebuild -scheme Telegram-iOS
   ```

2. **Запуск:**
   - Откройте приложение
   - Зайдите в Настройки
   - Должен быть пункт "AyuGram"

3. **Проверка Ghost Mode:**
   - Включите Режим Призрака
   - Откройте чат
   - Проверьте что "онлайн" не отображается у собеседника
   - Прочитайте сообщения - галочки не должны стать синими

4. **Проверка отложенной отправки:**
   - Включите отложенную отправку
   - Отправьте сообщение
   - "Последний раз в сети" не должен обновиться сразу

5. **Проверка сохранения удалённых:**
   - Включите сохранение удалённых
   - Попросите кого-то отправить и удалить сообщение
   - Сообщение должно остаться с пометкой "удалено"

---

## 🐛 Отладка

### Добавьте логирование:

```swift
// В AyuGramGhostMode.swift
public func shouldSendOnlineStatus() -> Bool {
    let result = !currentSettings.ghostModeEnabled || !currentSettings.preventOnlineStatus
    print("🔵 AYUGRAM: shouldSendOnlineStatus = \(result)")
    return result
}
```

### Используйте точки останова:

- Поставьте breakpoint в `updatePresence`
- Проверьте что `ayuGhostMode.shouldSendOnlineStatus()` вызывается
- Проверьте значение `currentSettings.ghostModeEnabled`

---

## 📚 Следующие шаги

После базовой интеграции:

1. ✅ Завершить интеграцию сохранения истории (нужен AccountStateManager.swift)
2. ✅ Добавить UI для просмотра удалённых сообщений
3. ✅ Добавить UI для просмотра истории изменений
4. ✅ Реализовать пересылку из приватных групп
5. ✅ Реализовать перехват исчезающих сообщений
6. ✅ Добавить экспорт/импорт настроек
7. ✅ Добавить статистику (сколько сообщений сохранено)

---

## 💡 Советы

1. **Делайте коммиты после каждого шага**
   ```bash
   git add .
   git commit -m "AyuGram: Добавлена базовая структура"
   ```

2. **Тестируйте на реальном устройстве**
   - Симулятор может не показывать некоторые проблемы
   - Особенно важно для networking

3. **Делайте резервные копии**
   - Перед большими изменениями
   - Сохраняйте оригинальные файлы

4. **Используйте feature flags**
   ```swift
   #if AYUGRAM
   // Код AyuGram
   #endif
   ```

---

## 🆘 Помощь

Если что-то не работает:

1. Проверьте что все файлы добавлены в проект
2. Проверьте что инициализация происходит до использования
3. Проверьте логи
4. Проверьте что передаются правильные экземпляры
5. Используйте отладчик

---

## ✨ Готово!

Базовая интеграция завершена. Теперь у вас есть:
- ✅ Режим Призрака (онлайн статус, read receipts, typing)
- ✅ Отложенная отправка сообщений
- ✅ Базовая структура для сохранения истории
- ✅ UI настроек

Следующий шаг - завершить интеграцию сохранения удалённых/изменённых сообщений (нужен AccountStateManager.swift).
