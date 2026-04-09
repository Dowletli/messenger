# Messenger Database Schema - Design Documentation

## Overview
This PostgreSQL schema supports a full-featured messenger application with:
- Direct messages (1-on-1)
- Group conversations
- Media attachments (images, videos, audio, files)
- Message reactions
- Threaded replies
- Read receipts
- Typing indicators

## Core Design Principles

### 1. **Scalability First**
- UUIDs instead of sequential IDs (better for distributed systems)
- Indexed foreign keys for fast joins
- Partitioning-ready timestamp columns
- JSONB for flexible metadata without schema changes

### 2. **Soft Deletes**
- `deleted_at` columns preserve data integrity
- Messages can be "unsent" without breaking conversations
- User accounts can be deactivated without cascade deletion

### 3. **Conversation-Centric Model**
- Single `conversations` table handles both DMs and groups
- Type discrimination via `type` column ('direct', 'group', 'channel')
- Participants tracked separately for flexible permissions

## Table Breakdown

### **users**
Core user information and authentication.
- `status`: Real-time presence (online/offline/away/busy)
- `last_seen_at`: Track when user was last active
- Indexes on username/email for login queries

### **conversations**
Container for all message exchanges.
- `type`: 'direct' (1-on-1), 'group' (named groups), 'channel' (broadcast)
- `name`: Required for groups, NULL for direct messages
- `created_by`: Track conversation creator

### **conversation_participants**
Many-to-many relationship with role-based permissions.
- `role`: 'owner', 'admin', 'member' for access control
- `last_read_message_id`: Track read position per user
- `muted_until`: Temporary notification muting
- Unique constraint prevents duplicate memberships

### **messages**
The heart of the system.
- `parent_message_id`: Enables threaded replies
- `message_type`: Distinguish text from media messages
- `metadata`: JSONB field for flexible data:
  ```json
  {
    "mentions": ["user-uuid-1", "user-uuid-2"],
    "links": ["https://example.com"],
    "forwarded_from": "message-uuid"
  }
  ```
- Composite index on `(conversation_id, created_at DESC)` for fast pagination

### **attachments**
Media files linked to messages.
- Separate table allows multiple attachments per message
- Stores metadata (dimensions, duration, thumbnails)
- `file_url`: Store actual files in S3/CDN, not database

### **reactions**
Emoji reactions on messages.
- Unique constraint: one user can only use same emoji once per message
- Can react multiple times with different emojis

### **message_reads**
Read receipts tracking.
- Alternative approach: Update `conversation_participants.last_read_message_id`
- This table provides granular "seen by" lists

### **contacts**
User relationship management.
- `blocked`: Prevent messages/calls from specific users
- `favorite`: Pin contacts to top
- `nickname`: Custom display names

## Key Queries & Performance

### Fetch conversation list for user
```sql
SELECT * FROM user_conversations 
WHERE user_id = 'user-uuid'
ORDER BY last_message_at DESC 
LIMIT 20;
```
Uses the `user_conversations` view with pre-calculated unread counts.

### Fetch messages with pagination
```sql
SELECT m.*, u.username, u.avatar_url,
       array_agg(DISTINCT a.*) as attachments,
       array_agg(DISTINCT r.*) as reactions
FROM messages m
JOIN users u ON u.id = m.sender_id
LEFT JOIN attachments a ON a.message_id = m.id
LEFT JOIN reactions r ON r.message_id = m.id
WHERE m.conversation_id = 'conv-uuid'
  AND m.deleted_at IS NULL
  AND m.created_at < 'cursor-timestamp'
GROUP BY m.id, u.id
ORDER BY m.created_at DESC
LIMIT 50;
```
Cursor-based pagination using timestamps for efficiency.

### Mark conversation as read
```sql
UPDATE conversation_participants
SET last_read_message_id = 'latest-message-uuid'
WHERE conversation_id = 'conv-uuid'
  AND user_id = 'user-uuid';
```

## Scaling Strategies

### Immediate Optimizations
1. **Message Partitioning**: Partition `messages` table by month/year
   ```sql
   CREATE TABLE messages_2024_01 PARTITION OF messages
   FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
   ```

2. **Read Replicas**: Direct read queries to replicas
   - Conversation lists
   - Message history
   - User searches

3. **Caching Layer** (Redis):
   - Online user status
   - Typing indicators (instead of DB table)
   - Recent conversation lists
   - Unread counts

### Future Considerations

#### When you hit 1M+ users:
- **Separate message storage**: Move to Cassandra/ScyllaDB for time-series message data
- **Event sourcing**: Store message events, rebuild state from events
- **Sharding**: Shard by conversation_id or user_id

#### For real-time features:
- Use WebSockets or Server-Sent Events
- Publish message events to Redis Pub/Sub or Kafka
- Don't poll `typing_indicators` table (use Redis TTL keys)

## Data Retention & Maintenance

### Regular Cleanup Jobs

1. **Old typing indicators** (every minute):
   ```sql
   DELETE FROM typing_indicators 
   WHERE started_at < NOW() - INTERVAL '30 seconds';
   ```

2. **Soft-deleted messages** (daily):
   ```sql
   DELETE FROM messages 
   WHERE deleted_at < NOW() - INTERVAL '30 days';
   ```

3. **Vacuum & Analyze** (weekly):
   ```sql
   VACUUM ANALYZE messages;
   VACUUM ANALYZE conversations;
   ```

## Security Considerations

### Before Production:
1. **Hash passwords**: Use bcrypt/argon2, never store plain text
2. **Encryption at rest**: Enable PostgreSQL data encryption
3. **Row-level security**: Add policies for multi-tenant isolation
4. **Rate limiting**: Prevent spam (app-level or pg_cron)
5. **File upload validation**: Scan attachments for malware

### Example RLS Policy:
```sql
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_select_policy ON messages
FOR SELECT USING (
    EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = messages.conversation_id
          AND user_id = current_setting('app.current_user_id')::uuid
          AND left_at IS NULL
    )
);
```

## Migration Path

### Phase 1: Core Messaging
- users, conversations, conversation_participants, messages
- Basic text messaging only

### Phase 2: Rich Media
- attachments table
- File upload service integration

### Phase 3: Engagement Features
- reactions, message_reads
- Typing indicators

### Phase 4: Advanced Features
- Threading (parent_message_id)
- Contacts & blocking
- Notification settings

## Testing Checklist

- [ ] Create direct conversation between two users
- [ ] Send text message with mentions in metadata
- [ ] Upload image with thumbnail
- [ ] Create group conversation with 5+ members
- [ ] Test admin/member role permissions
- [ ] Add reaction to message
- [ ] Reply to message (thread)
- [ ] Mark conversation as read
- [ ] Block user and verify no message delivery
- [ ] Soft delete message and verify it's hidden
- [ ] Query unread count view
- [ ] Load 100+ messages with pagination

## Monitoring Metrics

Watch these in production:
- Table sizes (especially `messages`)
- Index usage statistics
- Query performance (pg_stat_statements)
- Lock contention on high-traffic tables
- Replication lag (if using replicas)

---

**Questions or need help extending this?** Consider:
- Voice/video call metadata storage
- End-to-end encryption key management
- Search functionality (PostgreSQL full-text or Elasticsearch)
- Message translation/AI features
