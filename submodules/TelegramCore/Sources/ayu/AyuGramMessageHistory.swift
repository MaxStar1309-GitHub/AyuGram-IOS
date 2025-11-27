import Foundation
import SwiftSignalKit
import Postbox

// MARK: - Message History Manager
public final class AyuGramMessageHistory {
    private let settingsManager: AyuGramSettingsManager
    private let postbox: Postbox
    private var currentSettings: AyuGramSettings
    
    public init(settingsManager: AyuGramSettingsManager, postbox: Postbox) {
        self.settingsManager = settingsManager
        self.postbox = postbox
        self.currentSettings = .default
        
        // Загружаем настройки
        let _ = (settingsManager.getSettings()
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.currentSettings = settings
        })
    }
    
    // MARK: - Deleted Messages
    
    /// Проверяет, нужно ли сохранять удалённые сообщения
    public func shouldSaveDeletedMessages() -> Bool {
        return currentSettings.saveDeletedMessages
    }
    
    /// Сохраняет информацию об удалённом сообщении
    public func saveDeletedMessage(
        _ message: Message,
        deletedAt: Int32
    ) -> Signal<Void, NoError> {
        if !shouldSaveDeletedMessages() {
            return .complete()
        }
        
        return postbox.transaction { transaction -> Void in
            // Создаём запись об удалённом сообщении
            let deletedInfo = AyuDeletedMessageInfo(
                originalMessage: message,
                deletedAt: deletedAt,
                deletedBy: nil // TODO: определить кто удалил
            )
            
            // Сохраняем в кастомное хранилище
            self.storeDeletedMessage(deletedInfo, transaction: transaction)
            
            // Помечаем оригинальное сообщение как "удалённое AyuGram"
            self.markMessageAsDeleted(message, transaction: transaction)
        }
    }
    
    /// Сохраняет множество удалённых сообщений
    public func saveDeletedMessages(
        _ messages: [Message],
        deletedAt: Int32
    ) -> Signal<Void, NoError> {
        if !shouldSaveDeletedMessages() {
            return .complete()
        }
        
        return postbox.transaction { transaction -> Void in
            for message in messages {
                let deletedInfo = AyuDeletedMessageInfo(
                    originalMessage: message,
                    deletedAt: deletedAt,
                    deletedBy: nil
                )
                
                self.storeDeletedMessage(deletedInfo, transaction: transaction)
                self.markMessageAsDeleted(message, transaction: transaction)
            }
        }
    }
    
    /// Получает информацию об удалённом сообщении
    public func getDeletedMessageInfo(messageId: MessageId) -> Signal<AyuDeletedMessageInfo?, NoError> {
        return postbox.transaction { transaction -> AyuDeletedMessageInfo? in
            return self.retrieveDeletedMessage(messageId: messageId, transaction: transaction)
        }
    }
    
    /// Получает все удалённые сообщения для чата
    public func getDeletedMessages(peerId: PeerId) -> Signal<[AyuDeletedMessageInfo], NoError> {
        return postbox.transaction { transaction -> [AyuDeletedMessageInfo] in
            return self.retrieveDeletedMessages(peerId: peerId, transaction: transaction)
        }
    }
    
    // MARK: - Edited Messages
    
    /// Проверяет, нужно ли сохранять историю изменений сообщений
    public func shouldSaveEditedMessages() -> Bool {
        return currentSettings.saveEditedMessages
    }
    
    /// Сохраняет информацию об изменённом сообщении
    public func saveEditedMessage(
        originalMessage: Message,
        editedMessage: Message,
        editedAt: Int32
    ) -> Signal<Void, NoError> {
        if !shouldSaveEditedMessages() {
            return .complete()
        }
        
        return postbox.transaction { transaction -> Void in
            let editInfo = AyuMessageEditInfo(
                messageId: originalMessage.id,
                editedAt: editedAt,
                originalText: originalMessage.text,
                editedText: editedMessage.text,
                originalMedia: originalMessage.media,
                editedMedia: editedMessage.media
            )
            
            // Добавляем в историю изменений
            self.storeMessageEdit(editInfo, transaction: transaction)
        }
    }
    
    /// Получает историю изменений сообщения
    public func getMessageEditHistory(messageId: MessageId) -> Signal<[AyuMessageEditInfo], NoError> {
        return postbox.transaction { transaction -> [AyuMessageEditInfo] in
            return self.retrieveMessageEdits(messageId: messageId, transaction: transaction)
        }
    }
    
    /// Получает количество изменений для сообщения
    public func getEditCount(messageId: MessageId) -> Signal<Int, NoError> {
        return postbox.transaction { transaction -> Int in
            let edits = self.retrieveMessageEdits(messageId: messageId, transaction: transaction)
            return edits.count
        }
    }
    
    // MARK: - Private Storage Methods
    
    private func storeDeletedMessage(_ info: AyuDeletedMessageInfo, transaction: Transaction) {
        // Используем OrderedItemListTable для хранения
        let key = AyuStorageKey.deletedMessage(info.originalMessage.id)
        
        if let encoded = try? JSONEncoder().encode(info) {
            transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: AyuStorageKey.deletedMessagesCollection, key: key), entry: ItemCacheEntry(data: encoded))
        }
    }
    
    private func retrieveDeletedMessage(messageId: MessageId, transaction: Transaction) -> AyuDeletedMessageInfo? {
        let key = AyuStorageKey.deletedMessage(messageId)
        
        if let entry = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: AyuStorageKey.deletedMessagesCollection, key: key)),
           let info = try? JSONDecoder().decode(AyuDeletedMessageInfo.self, from: entry.data) {
            return info
        }
        
        return nil
    }
    
    private func retrieveDeletedMessages(peerId: PeerId, transaction: Transaction) -> [AyuDeletedMessageInfo] {
        // TODO: Реализовать получение всех удалённых сообщений для чата
        return []
    }
    
    private func markMessageAsDeleted(_ message: Message, transaction: Transaction) {
        // Добавляем специальный атрибут к сообщению
        transaction.updateMessage(message.id, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(
                    authorId: forwardInfo.author?.id,
                    sourceId: forwardInfo.source?.id,
                    sourceMessageId: forwardInfo.sourceMessageId,
                    date: forwardInfo.date,
                    authorSignature: forwardInfo.authorSignature,
                    psaType: forwardInfo.psaType,
                    flags: forwardInfo.flags
                )
            }
            
            var attributes = currentMessage.attributes
            attributes.append(AyuDeletedMessageAttribute())
            
            return .update(StoreMessage(
                id: currentMessage.id,
                globallyUniqueId: currentMessage.globallyUniqueId,
                groupingKey: currentMessage.groupingKey,
                threadId: currentMessage.threadId,
                timestamp: currentMessage.timestamp,
                flags: StoreMessageFlags(currentMessage.flags),
                tags: currentMessage.tags,
                globalTags: currentMessage.globalTags,
                localTags: currentMessage.localTags,
                forwardInfo: storeForwardInfo,
                authorId: currentMessage.author?.id,
                text: currentMessage.text,
                attributes: attributes,
                media: currentMessage.media
            ))
        })
    }
    
    private func storeMessageEdit(_ info: AyuMessageEditInfo, transaction: Transaction) {
        let key = AyuStorageKey.editedMessage(info.messageId, editIndex: 0) // TODO: использовать правильный индекс
        
        if let encoded = try? JSONEncoder().encode(info) {
            transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: AyuStorageKey.editedMessagesCollection, key: key), entry: ItemCacheEntry(data: encoded))
        }
    }
    
    private func retrieveMessageEdits(messageId: MessageId, transaction: Transaction) -> [AyuMessageEditInfo] {
        // TODO: Реализовать получение всех изменений сообщения
        return []
    }
}

// MARK: - Data Models

public struct AyuDeletedMessageInfo: Codable {
    let originalMessage: Message
    let deletedAt: Int32
    let deletedBy: PeerId?
    
    enum CodingKeys: String, CodingKey {
        case messageData
        case deletedAt
        case deletedBy
    }
    
    public init(originalMessage: Message, deletedAt: Int32, deletedBy: PeerId?) {
        self.originalMessage = originalMessage
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let messageData = try container.decode(Data.self, forKey: .messageData)
        // TODO: Десериализация Message из Data
        fatalError("Not implemented")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // TODO: Сериализация Message в Data
        try container.encode(deletedAt, forKey: .deletedAt)
        if let deletedBy = deletedBy {
            try container.encode(deletedBy.toInt64(), forKey: .deletedBy)
        }
    }
}

public struct AyuMessageEditInfo: Codable {
    let messageId: MessageId
    let editedAt: Int32
    let originalText: String
    let editedText: String
    // Упрощённое хранение медиа - только типы
    let originalMediaTypes: [String]
    let editedMediaTypes: [String]

    enum CodingKeys: String, CodingKey {
        case messageIdPeerId
        case messageIdNamespace
        case messageIdId
        case editedAt
        case originalText
        case editedText
        case originalMediaTypes
        case editedMediaTypes
    }

    public init(messageId: MessageId, editedAt: Int32, originalText: String, editedText: String, originalMedia: [Media], editedMedia: [Media]) {
        self.messageId = messageId
        self.editedAt = editedAt
        self.originalText = originalText
        self.editedText = editedText
        self.originalMediaTypes = originalMedia.map { String(describing: type(of: $0)) }
        self.editedMediaTypes = editedMedia.map { String(describing: type(of: $0)) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let peerId = try container.decode(Int64.self, forKey: .messageIdPeerId)
        let namespace = try container.decode(Int32.self, forKey: .messageIdNamespace)
        let id = try container.decode(Int32.self, forKey: .messageIdId)
        self.messageId = MessageId(peerId: PeerId(peerId), namespace: namespace, id: id)

        self.editedAt = try container.decode(Int32.self, forKey: .editedAt)
        self.originalText = try container.decode(String.self, forKey: .originalText)
        self.editedText = try container.decode(String.self, forKey: .editedText)
        self.originalMediaTypes = try container.decode([String].self, forKey: .originalMediaTypes)
        self.editedMediaTypes = try container.decode([String].self, forKey: .editedMediaTypes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(messageId.peerId.toInt64(), forKey: .messageIdPeerId)
        try container.encode(messageId.namespace, forKey: .messageIdNamespace)
        try container.encode(messageId.id, forKey: .messageIdId)
        try container.encode(editedAt, forKey: .editedAt)
        try container.encode(originalText, forKey: .originalText)
        try container.encode(editedText, forKey: .editedText)
        try container.encode(originalMediaTypes, forKey: .originalMediaTypes)
        try container.encode(editedMediaTypes, forKey: .editedMediaTypes)
    }
}


// MARK: - Custom Message Attribute
public class AyuDeletedMessageAttribute: MessageAttribute {
    public let associatedMessageIds: [MessageId] = []
    public let associatedMediaIds: [MediaId] = []
    
    public init() {}
    
    required public init(decoder: PostboxDecoder) {
        // Декодирование
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        // Кодирование
    }
}

// MARK: - Storage Keys
enum AyuStorageKey {
    static let deletedMessagesCollection: Int8 = 100
    static let editedMessagesCollection: Int8 = 101
    
    static func deletedMessage(_ messageId: MessageId) -> MemoryBuffer {
        let buffer = WriteBuffer()
        var id = messageId.id
        buffer.write(&id, offset: 0, length: 4)
        return buffer.makeData()
    }
    
    static func editedMessage(_ messageId: MessageId, editIndex: Int32) -> MemoryBuffer {
        let buffer = WriteBuffer()
        var id = messageId.id
        var index = editIndex
        buffer.write(&id, offset: 0, length: 4)
        buffer.write(&index, offset: 0, length: 4)
        return buffer.makeData()
    }
}

// MARK: - AccountStateManager Integration

extension AyuGramMessageHistory {
    /// Подписывается на события удаления сообщений из AccountStateManager
    /// ИСПОЛЬЗОВАНИЕ: вызвать при инициализации Account
    public func subscribeToDeletedMessages(
        stateManager: AccountStateManager
    ) -> Disposable {
        return stateManager.deletedMessages.start(next: { [weak self] deletedIds in
            guard let self = self else { return }
            guard self.shouldSaveDeletedMessages() else { return }

            print("🔴 AYUGRAM: Intercepted \(deletedIds.count) deleted message IDs")

            // Группируем по peer ID
            var messagesByPeer: [PeerId: [MessageId]] = [:]
            for deletedId in deletedIds {
                switch deletedId {
                case let .messageId(messageId):
                    if messagesByPeer[messageId.peerId] == nil {
                        messagesByPeer[messageId.peerId] = []
                    }
                    messagesByPeer[messageId.peerId]!.append(messageId)
                case let .global(globalId):
                    // Для глобальных ID создаём временный MessageId
                    // Это работает для обычных чатов и групп
                    // Для каналов используется .messageId
                    print("🟡 AYUGRAM: Global delete ID: \(globalId)")
                    // TODO: Обработка глобальных ID требует дополнительной логики
                    break
                }
            }

            // Сохраняем для каждого peer
            for (peerId, messageIds) in messagesByPeer {
                print("🟢 AYUGRAM: Saving \(messageIds.count) deleted messages for peer \(peerId)")
                let _ = self.handleDeletedMessages(
                    messageIds: messageIds,
                    peerId: peerId
                ).start()
            }
        })
    }

    /// Обрабатывает удалённые сообщения
    private func handleDeletedMessages(
        messageIds: [MessageId],
        peerId: PeerId
    ) -> Signal<Void, NoError> {
        return postbox.transaction { transaction -> Void in
            var messages: [Message] = []
            for messageId in messageIds {
                if let message = transaction.getMessage(messageId) {
                    messages.append(message)
                    print("📝 AYUGRAM: Found message to save: \(messageId)")
                } else {
                    print("⚠️ AYUGRAM: Message not found (already deleted?): \(messageId)")
                }
            }

            if !messages.isEmpty {
                let deletedAt = Int32(Date().timeIntervalSince1970)
                print("💾 AYUGRAM: Saving \(messages.count) deleted messages...")

                // Сохраняем через наш метод
                // ПРИМЕЧАНИЕ: saveDeletedMessages возвращает Signal, но мы в транзакции
                // Поэтому сохраняем синхронно
                for message in messages {
                    let deletedInfo = AyuDeletedMessageInfo(
                        originalMessage: message,
                        deletedAt: deletedAt,
                        deletedBy: nil
                    )

                    self.storeDeletedMessage(deletedInfo, transaction: transaction)
                    self.markMessageAsDeleted(message, transaction: transaction)
                }

                print("✅ AYUGRAM: Successfully saved \(messages.count) deleted messages")
            }
        }
    }
}

// MARK: - Direct transaction storage (for AccountStateManagementUtils)

extension AyuGramMessageHistory {
    /// Сохраняет изменение сообщения напрямую в транзакции
    /// Используется из AccountStateManagementUtils.swift
    public static func storeMessageEditDirectly(
        editInfo: AyuMessageEditInfo,
        transaction: Transaction
    ) {
        // Генерируем ключ для хранения
        let key = AyuStorageKey.editedMessage(editInfo.messageId, editIndex: 0)

        // TODO: Правильно подсчитывать editIndex (сколько раз уже редактировалось)
        // Пока используем 0, можно улучшить позже

        if let encoded = try? JSONEncoder().encode(editInfo) {
            transaction.putItemCacheEntry(
                id: ItemCacheEntryId(
                    collectionId: AyuStorageKey.editedMessagesCollection,
                    key: key
                ),
                entry: ItemCacheEntry(data: encoded)
            )

            print("✅ AYUGRAM: Edit info stored in Postbox")
        } else {
            print("❌ AYUGRAM: Failed to encode edit info")
        }
    }

    /// Получает историю изменений для сообщения
    public static func getMessageEditHistoryDirectly(
        messageId: MessageId,
        transaction: Transaction
    ) -> [AyuMessageEditInfo] {
        var edits: [AyuMessageEditInfo] = []

        // TODO: Получить все editIndex для данного messageId
        // Пока получаем только первое изменение
        let key = AyuStorageKey.editedMessage(messageId, editIndex: 0)

        if let entry = transaction.retrieveItemCacheEntry(
            id: ItemCacheEntryId(
                collectionId: AyuStorageKey.editedMessagesCollection,
                key: key
            )
        ) {
            if let info = try? JSONDecoder().decode(AyuMessageEditInfo.self, from: entry.data) {
                edits.append(info)
            }
        }

        return edits
    }
}