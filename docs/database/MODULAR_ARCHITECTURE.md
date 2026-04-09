# Messenger - Modular Monolith Architecture

## Overview
Based on the database schema, we can identify **6 core modules** with clear boundaries and responsibilities. Each module owns its tables and exposes a well-defined API to other modules.

---

## Module Breakdown

### 1. **User Management Module** 👤
**Responsibility**: User identity, authentication, profile management

**Owns Tables**:
- `users`
- `notification_settings`

**Core Functions**:
- User registration & authentication
- Profile CRUD (update display name, avatar, bio)
- User status management (online/offline/away/busy)
- Account deletion (soft delete)
- Notification preferences management

**Exposes API**:
```typescript
interface IUserService {
  // Authentication
  register(data: RegisterDto): Promise<User>
  login(credentials: LoginDto): Promise<AuthToken>
  logout(userId: UUID): Promise<void>
  
  // Profile
  getUser(userId: UUID): Promise<User>
  updateProfile(userId: UUID, data: ProfileUpdateDto): Promise<User>
  deleteAccount(userId: UUID): Promise<void>
  
  // Status
  updateStatus(userId: UUID, status: UserStatus): Promise<void>
  getOnlineUsers(userIds: UUID[]): Promise<User[]>
  
  // Notifications
  getNotificationSettings(userId: UUID): Promise<NotificationSettings>
  updateNotificationSettings(userId: UUID, settings: NotificationSettings): Promise<void>
}
```

**Dependencies**: None (foundational module)

**Events Published**:
- `UserRegistered`
- `UserProfileUpdated`
- `UserStatusChanged`
- `UserDeleted`

---

### 2. **Contacts Module** 🤝
**Responsibility**: User relationships, contact management, blocking

**Owns Tables**:
- `contacts`

**Core Functions**:
- Add/remove contacts
- Block/unblock users
- Favorite contacts
- Custom nicknames for contacts
- Get contact list with online status

**Exposes API**:
```typescript
interface IContactService {
  addContact(userId: UUID, contactId: UUID): Promise<Contact>
  removeContact(userId: UUID, contactId: UUID): Promise<void>
  getContacts(userId: UUID): Promise<Contact[]>
  
  // Blocking
  blockUser(userId: UUID, blockedUserId: UUID): Promise<void>
  unblockUser(userId: UUID, blockedUserId: UUID): Promise<void>
  isBlocked(userId: UUID, otherUserId: UUID): Promise<boolean>
  
  // Favorites
  toggleFavorite(userId: UUID, contactId: UUID): Promise<void>
  getFavorites(userId: UUID): Promise<Contact[]>
  
  // Nicknames
  setNickname(userId: UUID, contactId: UUID, nickname: string): Promise<void>
}
```

**Dependencies**: 
- User Management (to validate user existence)

**Events Published**:
- `ContactAdded`
- `ContactRemoved`
- `UserBlocked`
- `UserUnblocked`

---

### 3. **Conversation Module** 💬
**Responsibility**: Conversation lifecycle, participants, permissions

**Owns Tables**:
- `conversations`
- `conversation_participants`
- `typing_indicators`

**Core Functions**:
- Create/archive/delete conversations
- Manage participants (add/remove/roles)
- Direct message creation
- Group conversation creation
- Permission checks (who can send, who can add members)
- Typing indicators
- Read status tracking

**Exposes API**:
```typescript
interface IConversationService {
  // Conversation CRUD
  createDirectConversation(user1: UUID, user2: UUID): Promise<Conversation>
  createGroupConversation(creatorId: UUID, data: CreateGroupDto): Promise<Conversation>
  getConversation(conversationId: UUID): Promise<Conversation>
  updateConversation(conversationId: UUID, data: UpdateConversationDto): Promise<Conversation>
  archiveConversation(conversationId: UUID): Promise<void>
  deleteConversation(conversationId: UUID): Promise<void>
  
  // Participants
  addParticipants(conversationId: UUID, userIds: UUID[]): Promise<void>
  removeParticipant(conversationId: UUID, userId: UUID): Promise<void>
  leaveConversation(conversationId: UUID, userId: UUID): Promise<void>
  updateParticipantRole(conversationId: UUID, userId: UUID, role: Role): Promise<void>
  getParticipants(conversationId: UUID): Promise<Participant[]>
  
  // User's conversations
  getUserConversations(userId: UUID): Promise<ConversationListItem[]>
  getUnreadCount(userId: UUID, conversationId: UUID): Promise<number>
  
  // Permissions
  canUserSendMessage(userId: UUID, conversationId: UUID): Promise<boolean>
  canUserAddMembers(userId: UUID, conversationId: UUID): Promise<boolean>
  
  // Typing indicators
  setTyping(conversationId: UUID, userId: UUID): Promise<void>
  clearTyping(conversationId: UUID, userId: UUID): Promise<void>
  getTypingUsers(conversationId: UUID): Promise<UUID[]>
  
  // Read status
  markAsRead(conversationId: UUID, userId: UUID, messageId: UUID): Promise<void>
  muteConversation(conversationId: UUID, userId: UUID, until: Date): Promise<void>
}
```

**Dependencies**: 
- User Management (validate users)
- Contacts (check blocking status before creating DMs)

**Events Published**:
- `ConversationCreated`
- `ParticipantAdded`
- `ParticipantRemoved`
- `ParticipantRoleChanged`
- `UserTyping`
- `ConversationRead`

---

### 4. **Messaging Module** 📨
**Responsibility**: Message sending, editing, deletion, threading

**Owns Tables**:
- `messages`

**Core Functions**:
- Send text messages
- Edit messages
- Delete messages (soft delete)
- Thread/reply to messages
- Message search
- Message metadata (mentions, links)

**Exposes API**:
```typescript
interface IMessageService {
  // Send
  sendMessage(data: SendMessageDto): Promise<Message>
  sendReply(parentMessageId: UUID, data: SendMessageDto): Promise<Message>
  
  // Edit/Delete
  editMessage(messageId: UUID, userId: UUID, newContent: string): Promise<Message>
  deleteMessage(messageId: UUID, userId: UUID): Promise<void>
  
  // Query
  getMessages(conversationId: UUID, pagination: PaginationDto): Promise<Message[]>
  getMessage(messageId: UUID): Promise<Message>
  getThread(parentMessageId: UUID): Promise<Message[]>
  searchMessages(conversationId: UUID, query: string): Promise<Message[]>
  
  // Metadata
  extractMentions(content: string): UUID[]
  extractLinks(content: string): string[]
}
```

**Dependencies**: 
- Conversation (validate conversation exists, user is participant)
- User Management (validate sender)

**Events Published**:
- `MessageSent`
- `MessageEdited`
- `MessageDeleted`
- `UserMentioned`

---

### 5. **Media Module** 📎
**Responsibility**: File uploads, media attachments, CDN integration

**Owns Tables**:
- `attachments`

**Core Functions**:
- Upload files (images, videos, audio, documents)
- Generate thumbnails
- Store file metadata
- Integrate with S3/CDN
- Validate file types and sizes
- Get attachment URLs

**Exposes API**:
```typescript
interface IMediaService {
  // Upload
  uploadFile(file: File, uploadedBy: UUID): Promise<string> // returns file URL
  uploadImage(image: File, uploadedBy: UUID): Promise<ImageUploadResult>
  uploadVideo(video: File, uploadedBy: UUID): Promise<VideoUploadResult>
  
  // Attach to message
  attachToMessage(messageId: UUID, attachments: AttachmentDto[]): Promise<Attachment[]>
  
  // Query
  getAttachment(attachmentId: UUID): Promise<Attachment>
  getMessageAttachments(messageId: UUID): Promise<Attachment[]>
  
  // Validation
  validateFileType(file: File): boolean
  validateFileSize(file: File): boolean
  
  // Thumbnails
  generateThumbnail(imageUrl: string): Promise<string>
}
```

**Dependencies**: 
- Messaging (attach to messages)
- External: S3/CDN service

**Events Published**:
- `FileUploaded`
- `ThumbnailGenerated`

---

### 6. **Engagement Module** 💯
**Responsibility**: Reactions, read receipts, engagement tracking

**Owns Tables**:
- `reactions`
- `message_reads`

**Core Functions**:
- Add/remove reactions
- Track read receipts
- Get reaction counts
- Get "seen by" lists

**Exposes API**:
```typescript
interface IEngagementService {
  // Reactions
  addReaction(messageId: UUID, userId: UUID, emoji: string): Promise<Reaction>
  removeReaction(messageId: UUID, userId: UUID, emoji: string): Promise<void>
  getMessageReactions(messageId: UUID): Promise<ReactionSummary[]>
  
  // Read receipts
  markMessageAsRead(messageId: UUID, userId: UUID): Promise<void>
  getReadReceipts(messageId: UUID): Promise<ReadReceipt[]>
  hasUserReadMessage(messageId: UUID, userId: UUID): Promise<boolean>
}
```

**Dependencies**: 
- Messaging (validate message exists)
- User Management (validate user)

**Events Published**:
- `ReactionAdded`
- `ReactionRemoved`
- `MessageRead`

---

## Module Communication

### Communication Patterns

#### 1. **Direct API Calls** (Synchronous)
For immediate consistency needs:
```typescript
// Messaging Module calling Conversation Module
const canSend = await conversationService.canUserSendMessage(userId, conversationId);
if (!canSend) throw new ForbiddenError();
```

#### 2. **Event-Driven** (Asynchronous)
For loose coupling and side effects:
```typescript
// Messaging Module publishes event
eventBus.publish(new MessageSent({
  messageId,
  conversationId,
  senderId,
  content
}));

// Conversation Module subscribes
eventBus.subscribe('MessageSent', async (event) => {
  await this.updateConversationTimestamp(event.conversationId);
});
```

#### 3. **Dependency Injection**
```typescript
class MessageService {
  constructor(
    private conversationService: IConversationService,
    private userService: IUserService,
    private eventBus: IEventBus
  ) {}
}
```

---

## Module Dependency Graph

```
┌─────────────────────┐
│  User Management    │ ◄─── Foundational (no dependencies)
└──────────┬──────────┘
           │
           │ depends on
           │
           ▼
┌─────────────────────┐
│     Contacts        │
└──────────┬──────────┘
           │
           │ depends on
           │
           ▼
┌─────────────────────┐
│   Conversation      │ ◄─── Core orchestration
└──────────┬──────────┘
           │
           │ depends on
           ├──────────────────────┐
           │                      │
           ▼                      ▼
┌─────────────────────┐  ┌─────────────────────┐
│    Messaging        │  │   Engagement        │
└──────────┬──────────┘  └─────────────────────┘
           │
           │ depends on
           │
           ▼
┌─────────────────────┐
│      Media          │
└─────────────────────┘
```

---

## Folder Structure

```
src/
├── modules/
│   ├── user/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── User.ts
│   │   │   │   └── NotificationSettings.ts
│   │   │   └── repositories/
│   │   │       └── IUserRepository.ts
│   │   ├── application/
│   │   │   ├── services/
│   │   │   │   └── UserService.ts
│   │   │   ├── dtos/
│   │   │   └── events/
│   │   ├── infrastructure/
│   │   │   ├── persistence/
│   │   │   │   └── PostgresUserRepository.ts
│   │   │   └── api/
│   │   │       └── UserController.ts
│   │   └── index.ts (public exports)
│   │
│   ├── contacts/
│   │   ├── domain/
│   │   ├── application/
│   │   ├── infrastructure/
│   │   └── index.ts
│   │
│   ├── conversation/
│   │   ├── domain/
│   │   ├── application/
│   │   ├── infrastructure/
│   │   └── index.ts
│   │
│   ├── messaging/
│   │   ├── domain/
│   │   ├── application/
│   │   ├── infrastructure/
│   │   └── index.ts
│   │
│   ├── media/
│   │   ├── domain/
│   │   ├── application/
│   │   ├── infrastructure/
│   │   └── index.ts
│   │
│   └── engagement/
│       ├── domain/
│       ├── application/
│       ├── infrastructure/
│       └── index.ts
│
├── shared/
│   ├── domain/
│   │   ├── events/
│   │   │   └── EventBus.ts
│   │   └── types/
│   ├── infrastructure/
│   │   ├── database/
│   │   │   └── postgres.ts
│   │   └── cache/
│   │       └── redis.ts
│   └── utils/
│
└── main.ts
```

---

## Module Rules & Constraints

### ✅ DO:
1. **Each module owns its tables** - No other module writes directly to another's tables
2. **Use interfaces for cross-module communication** - Depend on abstractions, not implementations
3. **Publish domain events** - Notify other modules of important changes
4. **Keep module APIs minimal** - Only expose what's needed
5. **Module can access its own database directly** - No artificial data access layer between modules

### ❌ DON'T:
1. **No circular dependencies** - If A depends on B, B cannot depend on A
2. **No shared mutable state** - Pass data through APIs/events
3. **No database foreign keys across module boundaries** - Use UUIDs and eventual consistency
4. **No direct HTTP calls between modules** - They're in the same process, use direct method calls
5. **No business logic in shared folder** - Shared = utilities only

---

## Migration to Microservices (Future)

If you need to extract modules to separate services later:

### Easy to extract (loosely coupled):
- **Media Module** - Already designed for external storage
- **Engagement Module** - Event-driven, async by nature

### Medium difficulty:
- **Contacts Module** - Some synchronous calls needed
- **User Management** - Many modules depend on it (candidate for shared service)

### Hard to extract:
- **Messaging + Conversation** - Tightly coupled, high transaction volume

**Strategy**: Extract Media first, then Engagement. Keep core messaging as monolith.

---

## Example: Sending a Message (Cross-Module Flow)

```typescript
// 1. API Controller receives request
POST /conversations/:id/messages
{
  content: "Hello @john!",
  attachments: [{ fileId: "..." }]
}

// 2. Messaging Module orchestrates
class MessageService {
  async sendMessage(dto: SendMessageDto) {
    // Check permissions (Conversation Module)
    const canSend = await this.conversationService.canUserSendMessage(
      dto.senderId, 
      dto.conversationId
    );
    if (!canSend) throw new ForbiddenError();
    
    // Check if recipient blocked sender (Contacts Module)
    const participants = await this.conversationService.getParticipants(dto.conversationId);
    for (const participant of participants) {
      const isBlocked = await this.contactService.isBlocked(participant.userId, dto.senderId);
      if (isBlocked) throw new BlockedError();
    }
    
    // Create message
    const message = await this.messageRepository.create(dto);
    
    // Attach media (Media Module)
    if (dto.attachments?.length) {
      await this.mediaService.attachToMessage(message.id, dto.attachments);
    }
    
    // Publish event
    this.eventBus.publish(new MessageSent(message));
    
    return message;
  }
}

// 3. Other modules react to event
// Conversation Module updates last_message_at
eventBus.subscribe('MessageSent', async (event) => {
  await conversationService.updateTimestamp(event.conversationId);
});

// Engagement Module auto-marks as read for sender
eventBus.subscribe('MessageSent', async (event) => {
  await engagementService.markMessageAsRead(event.messageId, event.senderId);
});
```

---

## Summary

**6 Modules**:
1. User Management (users, auth, settings)
2. Contacts (relationships, blocking)
3. Conversation (conversations, participants, permissions)
4. Messaging (messages, threads)
5. Media (attachments, uploads)
6. Engagement (reactions, read receipts)

**Clear boundaries** + **Well-defined APIs** + **Event-driven communication** = **Maintainable modular monolith** ready to scale.
