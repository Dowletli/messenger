# Messenger Authentication Schema - Improvements Guide

## Overview
This document outlines the comprehensive authentication improvements made to the messenger database schema. The enhanced design provides enterprise-grade security, better user experience, and compliance with modern security standards.

---

## 🔐 Key Improvements

### 1. **Separated Credential Storage** (`user_credentials` table)
**Why**: Separating passwords from user profile data is a security best practice.

**Benefits**:
- Credentials are isolated from frequently-accessed user data
- Easier to apply different encryption/backup strategies
- Reduces risk if user table is compromised
- Password history tracking prevents reuse

**Fields**:
```sql
- password_hash: bcrypt/argon2 hashed password
- password_salt: Additional salt if needed
- password_changed_at: Track last password change
- password_history: Prevent password reuse (JSONB array)
- must_change_password: Force password reset flag
```

---

### 2. **Enhanced Session Management** (`user_sessions` table)
**Why**: Modern apps need to track multiple devices and provide security visibility.

**Benefits**:
- Users can see all active sessions
- Support for "logout everywhere" functionality
- Device fingerprinting for anomaly detection
- Audit trail for security investigations

**Features**:
- **Device tracking**: Type, name, ID
- **Location tracking**: Country, city (from IP)
- **Session lifecycle**: Created, last activity, expiration
- **Refresh tokens**: For seamless token rotation
- **Revocation reasons**: Track why sessions ended

**Use Cases**:
```javascript
// User sees: "iPhone 13 Pro - Los Angeles, US - Active 2 hours ago"
// Can revoke suspicious sessions
// Admin can terminate all sessions for compromised account
```

---

### 3. **Two-Factor Authentication** (`two_factor_auth` table)
**Why**: Essential for account security in modern applications.

**Supported Methods**:
- **TOTP** (Time-based One-Time Password) - Google Authenticator, Authy
- **SMS** - Text message codes
- **Email** - Email-based codes
- **Backup codes** - One-time emergency codes

**Fields**:
```sql
- method: Which 2FA method is active
- secret_key: Encrypted TOTP secret
- backup_codes: Hashed one-time codes (JSONB array)
- verified: Ensure 2FA is properly set up
- last_used_at: Track usage patterns
```

---

### 4. **Verification System** (`verification_tokens` table)
**Why**: Unified system for all token-based verifications.

**Token Types**:
- Email verification (new account)
- Phone verification
- Password reset
- Magic link login (passwordless)

**Security Features**:
- **Hashed tokens**: Never store plaintext
- **Expiration**: Time-limited validity
- **Attempt limiting**: Max 3 tries prevents brute force
- **Single use**: Tokens invalidated after use

**Example Flow**:
```
1. User requests password reset
2. Generate random token, hash it, store hash
3. Send original token via email
4. User submits token
5. Hash submitted token, compare to stored hash
6. If match and not expired: allow password reset
7. Mark token as used
```

---

### 5. **Security Monitoring** (`login_attempts` & `security_events` tables)

#### `login_attempts`
**Purpose**: Track all login attempts for rate limiting and security.

**Benefits**:
- Detect brute force attacks
- Automatic account locking after N failed attempts
- IP-based rate limiting
- Identify credential stuffing attacks

**Metrics You Can Track**:
```sql
-- Failed logins in last hour for a user
-- Failed logins from an IP address
-- Success rate by region
-- Most common failure reasons
```

#### `security_events`
**Purpose**: Complete audit log of security-related actions.

**Event Types**:
- Password changes
- 2FA enabled/disabled
- Account locked/unlocked
- Suspicious login detected
- Session revoked
- OAuth provider linked/unlinked

**Use Cases**:
- Notify users of critical security events
- Compliance auditing (GDPR, SOC2)
- Forensic analysis after breach
- User transparency (security dashboard)

---

### 6. **OAuth/Social Login** (`oauth_providers` table)
**Why**: Users expect social login options.

**Supported Providers**:
- Google
- Facebook
- Apple
- GitHub
- Microsoft

**Features**:
- **Multiple providers**: Link several OAuth accounts
- **Token management**: Store encrypted access/refresh tokens
- **Profile sync**: Keep provider data updated
- **Revocation**: Unlink accounts anytime

**Security Considerations**:
```sql
- access_token: ENCRYPTED (AES-256)
- refresh_token: ENCRYPTED
- provider_user_id: Unique identifier from provider
```

---

### 7. **API Key Management** (`api_keys` table)
**Why**: For programmatic access to messenger platform.

**Features**:
- **Named keys**: "Mobile App", "CI/CD Pipeline", etc.
- **Scoped permissions**: Limit what each key can do
- **Usage tracking**: Monitor API calls per key
- **Rate limiting**: Prevent abuse
- **Expiration**: Time-limited keys for temporary access
- **Prefix display**: Show first characters for identification

**Example**:
```
Key: mk_live_abc123xyz789... (full key given once)
Display: mk_live_abc1... (only prefix stored/shown)
Stored: hash(full_key) (one-way hash in database)
```

---

### 8. **Trusted Devices** (`trusted_devices` table)
**Why**: Improve UX while maintaining security.

**Functionality**:
- Remember devices user has verified via 2FA
- Skip 2FA on trusted devices (configurable)
- Time-limited trust (e.g., 30 days)
- Device fingerprinting for identification

**User Experience**:
```
First login from new device:
  → Enter password + 2FA code
  → "Trust this device for 30 days?" ✓
  
Subsequent logins from same device:
  → Enter password only (no 2FA)
  
After 30 days or if revoked:
  → Require 2FA again
```

---

### 9. **Rate Limiting** (`rate_limits` table)
**Why**: Prevent abuse and protect system resources.

**Configurable Limits**:
```javascript
{
  login: "5 attempts per 15 minutes per IP",
  send_message: "100 messages per hour per user",
  api_call: "1000 requests per hour per API key",
  password_reset: "3 requests per day per user"
}
```

**Note**: This table is suitable for MVP. For production at scale, use **Redis** with sliding window algorithm.

---

### 10. **Enhanced User Fields**

**New Security Fields in `users` table**:
```sql
- email_verified: Ensure valid email ownership
- phone_verified: Ensure valid phone ownership
- two_factor_enabled: Quick check for 2FA status
- account_locked: Prevent access to compromised accounts
- locked_until: Temporary lock duration
- locked_reason: Why account was locked (for user transparency)
```

---

## 📊 Database Schema Improvements Summary

| Feature | Before | After |
|---------|--------|-------|
| Password Storage | In users table | Separate `user_credentials` table |
| Session Tracking | None | Full `user_sessions` with device info |
| 2FA Support | None | Complete `two_factor_auth` system |
| OAuth Login | None | `oauth_providers` table |
| Security Auditing | None | `login_attempts` + `security_events` |
| Verification System | None | Unified `verification_tokens` |
| API Access | None | `api_keys` with scoping |
| Trusted Devices | None | `trusted_devices` for better UX |
| Rate Limiting | None | `rate_limits` table (or Redis) |

---

## 🚀 Implementation Recommendations

### 1. **Migration Strategy**
```sql
-- Step 1: Create new tables
-- Step 2: Migrate existing user.password_hash to user_credentials
-- Step 3: Create initial sessions for logged-in users
-- Step 4: Add indexes for performance
-- Step 5: Deploy application code changes
```

### 2. **Security Best Practices**

**Password Hashing**:
```javascript
// Use Argon2id (recommended) or bcrypt
const hash = await argon2.hash(password, {
  type: argon2.argon2id,
  memoryCost: 65536,
  timeCost: 3,
  parallelism: 4
});
```

**Token Generation**:
```javascript
// Use cryptographically secure random
const crypto = require('crypto');
const token = crypto.randomBytes(32).toString('hex');
const hash = crypto.createHash('sha256').update(token).digest('hex');
// Send 'token' to user, store 'hash' in database
```

**Session Tokens**:
```javascript
// JWT or secure random string
// Store hash of token, not plaintext
// Implement token rotation
```

### 3. **Performance Considerations**

**Indexes** (already included in schema):
```sql
-- Critical for performance
CREATE INDEX idx_sessions_active ON user_sessions(user_id, revoked_at) 
  WHERE revoked_at IS NULL;

CREATE INDEX idx_login_attempts_recent ON login_attempts(ip_address, attempted_at) 
  WHERE success = false;

CREATE INDEX idx_verification_tokens_valid ON verification_tokens(expires_at) 
  WHERE used_at IS NULL;
```

**Partitioning** (for high volume):
```sql
-- Partition login_attempts by month
-- Archive old security_events
-- Use Redis for rate_limits in production
```

### 4. **Privacy & Compliance**

**GDPR Considerations**:
- `ip_address`: Personal data - must be disclosed in privacy policy
- `user_agent`: Personal data
- Right to access: Export all user security data
- Right to deletion: Cascade deletes or anonymize
- Data retention: Archive old login attempts/security events

**Encryption**:
```sql
-- Encrypt at rest (sensitive fields):
- user_credentials.password_hash (hashed, not encrypted)
- two_factor_auth.secret_key (ENCRYPTED)
- oauth_providers.access_token (ENCRYPTED)
- oauth_providers.refresh_token (ENCRYPTED)
```

---

## 🔧 Feature Implementation Examples

### Example 1: Login Flow
```javascript
async function login(username, password, ipAddress, userAgent) {
  // 1. Check rate limits
  if (await isRateLimited(ipAddress, 'login')) {
    throw new Error('Too many attempts. Try again later.');
  }
  
  // 2. Find user
  const user = await findUserByUsername(username);
  if (!user) {
    await logLoginAttempt(null, username, ipAddress, false, 'user_not_found');
    throw new Error('Invalid credentials');
  }
  
  // 3. Check if account is locked
  if (user.account_locked && user.locked_until > new Date()) {
    await logLoginAttempt(user.id, username, ipAddress, false, 'account_locked');
    throw new Error('Account temporarily locked');
  }
  
  // 4. Verify password
  const credentials = await getUserCredentials(user.id);
  const valid = await verifyPassword(password, credentials.password_hash);
  
  if (!valid) {
    await logLoginAttempt(user.id, username, ipAddress, false, 'invalid_password');
    await incrementFailedAttempts(user.id, ipAddress);
    throw new Error('Invalid credentials');
  }
  
  // 5. Check if 2FA is enabled
  if (user.two_factor_enabled) {
    // Return temporary token requiring 2FA completion
    return { requires2FA: true, tempToken: generateTempToken(user.id) };
  }
  
  // 6. Create session
  const session = await createSession(user.id, ipAddress, userAgent);
  await logLoginAttempt(user.id, username, ipAddress, true, null);
  
  return { sessionToken: session.token, user };
}
```

### Example 2: 2FA Verification
```javascript
async function verify2FA(userId, code) {
  const twoFA = await getTwoFactorAuth(userId);
  
  if (twoFA.method === 'totp') {
    const valid = verifyTOTP(code, twoFA.secret_key);
    if (!valid) throw new Error('Invalid code');
  } else if (twoFA.method === 'sms') {
    // Verify against sent SMS code (stored in verification_tokens)
    const valid = await verifyToken(userId, code, 'sms_2fa');
    if (!valid) throw new Error('Invalid code');
  }
  
  await updateTwoFactorLastUsed(userId);
  return true;
}
```

### Example 3: Password Reset Flow
```javascript
async function requestPasswordReset(email) {
  const user = await findUserByEmail(email);
  if (!user) return; // Don't reveal if user exists
  
  // Generate secure token
  const token = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  
  // Store hashed token
  await createVerificationToken({
    user_id: user.id,
    token_hash: tokenHash,
    token_type: 'password_reset',
    delivery_method: 'email',
    delivery_address: email,
    expires_at: new Date(Date.now() + 3600000) // 1 hour
  });
  
  // Send email with original token (not hash)
  await sendEmail(email, `Reset link: https://app.com/reset?token=${token}`);
}

async function resetPassword(token, newPassword) {
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  
  // Find valid token
  const verification = await findVerificationToken(tokenHash, 'password_reset');
  if (!verification || verification.expires_at < new Date()) {
    throw new Error('Invalid or expired token');
  }
  if (verification.used_at) {
    throw new Error('Token already used');
  }
  if (verification.attempts >= verification.max_attempts) {
    throw new Error('Too many attempts');
  }
  
  // Update password
  const hash = await hashPassword(newPassword);
  await updateUserCredentials(verification.user_id, hash);
  
  // Mark token as used
  await markTokenUsed(verification.id);
  
  // Log security event
  await logSecurityEvent(verification.user_id, 'password_changed', 'medium');
  
  // Revoke all sessions (force re-login)
  await revokeAllUserSessions(verification.user_id, 'password_reset');
}
```

---

## 📈 Monitoring & Analytics

### Key Metrics to Track
```sql
-- Login success rate
SELECT 
  DATE(attempted_at) as date,
  COUNT(*) FILTER (WHERE success = true) * 100.0 / COUNT(*) as success_rate
FROM login_attempts
GROUP BY DATE(attempted_at);

-- Active sessions per user
SELECT user_id, COUNT(*) as active_sessions
FROM user_sessions
WHERE revoked_at IS NULL AND expires_at > NOW()
GROUP BY user_id;

-- 2FA adoption rate
SELECT 
  COUNT(*) FILTER (WHERE two_factor_enabled = true) * 100.0 / COUNT(*) as adoption_rate
FROM users;

-- Security events by severity
SELECT severity, event_type, COUNT(*)
FROM security_events
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY severity, event_type;
```

---

## ✅ Checklist for Production Deployment

- [ ] Migrate data from old schema
- [ ] Implement password hashing (Argon2id/bcrypt)
- [ ] Set up email/SMS providers for verification
- [ ] Configure OAuth providers
- [ ] Implement token generation/validation
- [ ] Add rate limiting middleware
- [ ] Set up session cleanup job (delete expired sessions)
- [ ] Implement security event notifications
- [ ] Add admin dashboard for security monitoring
- [ ] Test all authentication flows
- [ ] Set up database backups with encryption
- [ ] Configure application-level encryption for sensitive fields
- [ ] Add logging and monitoring
- [ ] Document security policies
- [ ] Conduct security audit/penetration testing

---

## 🆘 Common Questions

**Q: Should I store password_hash even when using OAuth?**
A: Yes, allow users to set a password as backup. OAuth providers can revoke access.

**Q: How long should sessions last?**
A: Typical: 7-30 days for web, 90+ days for mobile. Use refresh tokens for security.

**Q: Should I use this rate_limits table in production?**
A: For MVP, yes. For production scale (>10K users), use Redis with sliding window.

**Q: How do I handle password history?**
A: Store last 5-10 password hashes in JSONB array. Check new password against them.

**Q: What about magic link login?**
A: Use verification_tokens with token_type='magic_link'. Same security as password reset.

---

## 📚 Additional Resources

- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [NIST Password Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8725)
- [2FA Implementation Guide](https://www.twilio.com/docs/verify/quickstarts)

---

**Version**: 1.0  
**Last Updated**: April 2026  
**Maintained by**: Your Team
