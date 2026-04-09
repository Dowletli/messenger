-- ============================================================================
-- MESSENGER APP - AUTHENTICATION ENHANCEMENT MIGRATION
-- ============================================================================
-- This migration enhances the authentication system with modern security features
-- Run this after backing up your database
-- 
-- Features added:
-- - Separated credential storage
-- - Session management with device tracking
-- - Two-factor authentication
-- - OAuth/Social login support
-- - Security event logging
-- - API key management
-- - Trusted devices
-- - Rate limiting
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. MODIFY EXISTING USERS TABLE
-- ============================================================================

-- Add new security fields to existing users table
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS account_locked BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS locked_reason TEXT;

-- Add new indexes
CREATE INDEX IF NOT EXISTS idx_users_email_phone_verified 
  ON users(email_verified, phone_verified);

-- Remove password_hash from users table (will be moved to user_credentials)
-- COMMENT: Do this AFTER migrating data to user_credentials table
-- ALTER TABLE users DROP COLUMN IF EXISTS password_hash;

-- ============================================================================
-- 2. CREATE USER_CREDENTIALS TABLE (Separate password storage)
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_credentials (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  password_hash VARCHAR(255) NOT NULL,
  password_salt VARCHAR(255),
  password_changed_at TIMESTAMPTZ DEFAULT NOW(),
  password_history JSONB DEFAULT '[]'::jsonb,
  must_change_password BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_credentials_user_id ON user_credentials(user_id);

COMMENT ON TABLE user_credentials IS 'Separated credential storage for enhanced security';
COMMENT ON COLUMN user_credentials.password_hash IS 'bcrypt or argon2 hashed password';
COMMENT ON COLUMN user_credentials.password_history IS 'Array of previous password hashes to prevent reuse';

-- ============================================================================
-- 3. CREATE USER_SESSIONS TABLE (Session management)
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_token VARCHAR(255) UNIQUE NOT NULL,
  refresh_token VARCHAR(255) UNIQUE,
  device_id VARCHAR(255),
  device_name VARCHAR(100),
  device_type VARCHAR(50),
  ip_address INET,
  user_agent TEXT,
  location_country VARCHAR(2),
  location_city VARCHAR(100),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_activity_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  revoked_reason VARCHAR(50)
);

CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(session_token);
CREATE INDEX idx_sessions_refresh_token ON user_sessions(refresh_token);
CREATE INDEX idx_sessions_device_id ON user_sessions(device_id);
CREATE INDEX idx_sessions_active ON user_sessions(user_id, revoked_at) 
  WHERE revoked_at IS NULL;
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);

COMMENT ON TABLE user_sessions IS 'Track all user sessions with device and location info';
COMMENT ON COLUMN user_sessions.device_type IS 'mobile, desktop, web, tablet';
COMMENT ON COLUMN user_sessions.revoked_reason IS 'user_logout, admin_action, suspicious_activity, expired';

-- ============================================================================
-- 4. CREATE TWO_FACTOR_AUTH TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS two_factor_auth (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  method VARCHAR(20) NOT NULL,
  secret_key VARCHAR(255),
  backup_codes JSONB,
  phone_number VARCHAR(20),
  email VARCHAR(255),
  enabled BOOLEAN DEFAULT true,
  verified BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ
);

CREATE INDEX idx_2fa_user_id ON two_factor_auth(user_id);
CREATE INDEX idx_2fa_method ON two_factor_auth(method);

COMMENT ON TABLE two_factor_auth IS 'Two-factor authentication settings';
COMMENT ON COLUMN two_factor_auth.method IS 'totp, sms, email, backup_codes';
COMMENT ON COLUMN two_factor_auth.secret_key IS 'Encrypted TOTP secret for authenticator apps';
COMMENT ON COLUMN two_factor_auth.backup_codes IS 'Hashed one-time backup codes';

-- ============================================================================
-- 5. CREATE VERIFICATION_TOKENS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS verification_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) UNIQUE NOT NULL,
  token_type VARCHAR(50) NOT NULL,
  delivery_method VARCHAR(20),
  delivery_address VARCHAR(255),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  attempts INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 3
);

CREATE INDEX idx_verification_token_hash ON verification_tokens(token_hash);
CREATE INDEX idx_verification_user_id ON verification_tokens(user_id);
CREATE INDEX idx_verification_type_expires ON verification_tokens(token_type, expires_at);
CREATE INDEX idx_verification_valid ON verification_tokens(expires_at) 
  WHERE used_at IS NULL;

COMMENT ON TABLE verification_tokens IS 'Tokens for email verification, password reset, magic links';
COMMENT ON COLUMN verification_tokens.token_type IS 'email_verification, phone_verification, password_reset, magic_link';
COMMENT ON COLUMN verification_tokens.token_hash IS 'SHA-256 hash of the actual token sent to user';

-- ============================================================================
-- 6. CREATE LOGIN_ATTEMPTS TABLE (Security monitoring)
-- ============================================================================

CREATE TABLE IF NOT EXISTS login_attempts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  username_attempted VARCHAR(255) NOT NULL,
  ip_address INET NOT NULL,
  user_agent TEXT,
  success BOOLEAN NOT NULL,
  failure_reason VARCHAR(50),
  attempted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_login_user_id ON login_attempts(user_id);
CREATE INDEX idx_login_ip ON login_attempts(ip_address);
CREATE INDEX idx_login_attempted_at ON login_attempts(attempted_at);
CREATE INDEX idx_login_failed_by_user ON login_attempts(user_id, attempted_at) 
  WHERE success = false;
CREATE INDEX idx_login_failed_by_ip ON login_attempts(ip_address, attempted_at) 
  WHERE success = false;

COMMENT ON TABLE login_attempts IS 'Track all login attempts for security monitoring';
COMMENT ON COLUMN login_attempts.failure_reason IS 'invalid_password, account_locked, user_not_found, 2fa_failed';

-- ============================================================================
-- 7. CREATE SECURITY_EVENTS TABLE (Audit log)
-- ============================================================================

CREATE TABLE IF NOT EXISTS security_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  event_type VARCHAR(50) NOT NULL,
  severity VARCHAR(20),
  ip_address INET,
  user_agent TEXT,
  metadata JSONB,
  notified BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_security_events_user_id ON security_events(user_id);
CREATE INDEX idx_security_events_type ON security_events(event_type);
CREATE INDEX idx_security_events_severity ON security_events(severity);
CREATE INDEX idx_security_events_created_at ON security_events(created_at);
CREATE INDEX idx_security_events_metadata ON security_events USING gin(metadata);

COMMENT ON TABLE security_events IS 'Audit log for security-related events';
COMMENT ON COLUMN security_events.event_type IS 'password_changed, 2fa_enabled, account_locked, suspicious_login, etc.';
COMMENT ON COLUMN security_events.severity IS 'low, medium, high, critical';

-- ============================================================================
-- 8. CREATE OAUTH_PROVIDERS TABLE (Social login)
-- ============================================================================

CREATE TABLE IF NOT EXISTS oauth_providers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(50) NOT NULL,
  provider_user_id VARCHAR(255) NOT NULL,
  email VARCHAR(255),
  access_token TEXT,
  refresh_token TEXT,
  token_expires_at TIMESTAMPTZ,
  profile_data JSONB,
  
  linked_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_oauth_user_id ON oauth_providers(user_id);
CREATE INDEX idx_oauth_provider ON oauth_providers(provider);
CREATE UNIQUE INDEX idx_oauth_provider_user ON oauth_providers(provider, provider_user_id);

COMMENT ON TABLE oauth_providers IS 'OAuth and social login integration';
COMMENT ON COLUMN oauth_providers.provider IS 'google, facebook, apple, github, microsoft';
COMMENT ON COLUMN oauth_providers.access_token IS 'Should be encrypted at application level';
COMMENT ON COLUMN oauth_providers.refresh_token IS 'Should be encrypted at application level';

-- ============================================================================
-- 9. CREATE API_KEYS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS api_keys (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_hash VARCHAR(255) UNIQUE NOT NULL,
  key_prefix VARCHAR(10) NOT NULL,
  name VARCHAR(100) NOT NULL,
  scopes JSONB,
  
  last_used_at TIMESTAMPTZ,
  last_used_ip INET,
  usage_count BIGINT DEFAULT 0,
  rate_limit INTEGER,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX idx_api_keys_hash ON api_keys(key_hash);
CREATE INDEX idx_api_keys_active ON api_keys(user_id, revoked_at) 
  WHERE revoked_at IS NULL;

COMMENT ON TABLE api_keys IS 'API keys for programmatic access';
COMMENT ON COLUMN api_keys.key_hash IS 'SHA-256 hash of the full API key';
COMMENT ON COLUMN api_keys.key_prefix IS 'First few characters shown to user for identification';
COMMENT ON COLUMN api_keys.scopes IS 'JSON array of permissions';

-- ============================================================================
-- 10. CREATE TRUSTED_DEVICES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS trusted_devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id VARCHAR(255) UNIQUE NOT NULL,
  device_name VARCHAR(100),
  device_type VARCHAR(50),
  fingerprint_hash VARCHAR(255),
  
  first_seen_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ DEFAULT NOW(),
  trusted_at TIMESTAMPTZ,
  trust_expires_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

CREATE INDEX idx_trusted_devices_user_id ON trusted_devices(user_id);
CREATE INDEX idx_trusted_devices_device_id ON trusted_devices(device_id);
CREATE INDEX idx_trusted_devices_active ON trusted_devices(user_id, trusted_at) 
  WHERE revoked_at IS NULL AND trust_expires_at > NOW();

COMMENT ON TABLE trusted_devices IS 'Remember trusted devices to skip 2FA';
COMMENT ON COLUMN trusted_devices.fingerprint_hash IS 'Browser/device fingerprint hash';

-- ============================================================================
-- 11. CREATE RATE_LIMITS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS rate_limits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  identifier VARCHAR(255) NOT NULL,
  identifier_type VARCHAR(50) NOT NULL,
  action VARCHAR(50) NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  window_duration INTERVAL NOT NULL,
  request_count INTEGER DEFAULT 0,
  max_requests INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_rate_limits_unique ON rate_limits(identifier, action, window_start);
CREATE INDEX idx_rate_limits_type_action ON rate_limits(identifier_type, action);
CREATE INDEX idx_rate_limits_window ON rate_limits(window_start);

COMMENT ON TABLE rate_limits IS 'Rate limiting tracking - consider Redis for production';
COMMENT ON COLUMN rate_limits.identifier IS 'user_id, ip_address, or api_key';
COMMENT ON COLUMN rate_limits.identifier_type IS 'user, ip, api_key';
COMMENT ON COLUMN rate_limits.action IS 'login, send_message, api_call, password_reset';

-- ============================================================================
-- 12. DATA MIGRATION - Move password_hash to user_credentials
-- ============================================================================

-- Only run if password_hash exists in users table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'users' AND column_name = 'password_hash'
  ) THEN
    -- Migrate existing password hashes
    INSERT INTO user_credentials (user_id, password_hash, password_changed_at)
    SELECT id, password_hash, created_at
    FROM users
    WHERE password_hash IS NOT NULL
    ON CONFLICT (user_id) DO NOTHING;
    
    RAISE NOTICE 'Migrated password hashes to user_credentials table';
  END IF;
END $$;

-- ============================================================================
-- 13. CREATE HELPER FUNCTIONS
-- ============================================================================

-- Function to clean up expired sessions
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM user_sessions 
  WHERE expires_at < NOW() 
    AND revoked_at IS NULL;
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_expired_sessions IS 'Delete expired sessions - run as scheduled job';

-- Function to clean up old verification tokens
CREATE OR REPLACE FUNCTION cleanup_old_verification_tokens()
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM verification_tokens 
  WHERE expires_at < NOW() - INTERVAL '7 days';
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_verification_tokens IS 'Delete expired tokens older than 7 days';

-- Function to update session activity
CREATE OR REPLACE FUNCTION update_session_activity(session_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE user_sessions 
  SET last_activity_at = NOW()
  WHERE id = session_id;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to tables with updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at 
  BEFORE UPDATE ON users 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_user_credentials_updated_at ON user_credentials;
CREATE TRIGGER update_user_credentials_updated_at 
  BEFORE UPDATE ON user_credentials 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_two_factor_auth_updated_at ON two_factor_auth;
CREATE TRIGGER update_two_factor_auth_updated_at 
  BEFORE UPDATE ON two_factor_auth 
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 14. CREATE VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View for active sessions with user info
CREATE OR REPLACE VIEW active_sessions_view AS
SELECT 
  s.id,
  s.user_id,
  u.username,
  u.email,
  s.device_name,
  s.device_type,
  s.ip_address,
  s.location_city,
  s.location_country,
  s.created_at,
  s.last_activity_at,
  s.expires_at
FROM user_sessions s
JOIN users u ON u.id = s.user_id
WHERE s.revoked_at IS NULL 
  AND s.expires_at > NOW();

COMMENT ON VIEW active_sessions_view IS 'All currently active user sessions';

-- View for recent failed login attempts
CREATE OR REPLACE VIEW recent_failed_logins AS
SELECT 
  user_id,
  username_attempted,
  ip_address,
  failure_reason,
  attempted_at,
  COUNT(*) OVER (PARTITION BY user_id) as user_fail_count,
  COUNT(*) OVER (PARTITION BY ip_address) as ip_fail_count
FROM login_attempts
WHERE success = false 
  AND attempted_at > NOW() - INTERVAL '1 hour'
ORDER BY attempted_at DESC;

COMMENT ON VIEW recent_failed_logins IS 'Failed login attempts in the last hour';

-- View for security dashboard
CREATE OR REPLACE VIEW security_dashboard AS
SELECT 
  u.id as user_id,
  u.username,
  u.email,
  u.email_verified,
  u.phone_verified,
  u.two_factor_enabled,
  u.account_locked,
  COUNT(DISTINCT s.id) as active_sessions,
  COUNT(DISTINCT td.id) as trusted_devices,
  COUNT(DISTINCT op.id) as oauth_providers,
  MAX(s.last_activity_at) as last_activity,
  (
    SELECT COUNT(*) 
    FROM login_attempts la 
    WHERE la.user_id = u.id 
      AND la.success = false 
      AND la.attempted_at > NOW() - INTERVAL '24 hours'
  ) as failed_logins_24h
FROM users u
LEFT JOIN user_sessions s ON s.user_id = u.id 
  AND s.revoked_at IS NULL 
  AND s.expires_at > NOW()
LEFT JOIN trusted_devices td ON td.user_id = u.id 
  AND td.revoked_at IS NULL
LEFT JOIN oauth_providers op ON op.user_id = u.id 
  AND op.revoked_at IS NULL
WHERE u.deleted_at IS NULL
GROUP BY u.id;

COMMENT ON VIEW security_dashboard IS 'Security overview for each user';

-- ============================================================================
-- 15. GRANT PERMISSIONS (Adjust as needed for your setup)
-- ============================================================================

-- Example: Grant permissions to application role
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_user;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

COMMIT;

-- ============================================================================
-- POST-MIGRATION CHECKLIST
-- ============================================================================
-- [ ] Verify all tables created successfully
-- [ ] Check that password_hash data migrated to user_credentials
-- [ ] Test authentication flow with new schema
-- [ ] Set up scheduled job to run cleanup_expired_sessions() daily
-- [ ] Set up scheduled job to run cleanup_old_verification_tokens() weekly
-- [ ] Update application code to use new tables
-- [ ] Implement password hashing (bcrypt/argon2)
-- [ ] Implement token generation and validation
-- [ ] Set up email/SMS providers for verification
-- [ ] Configure OAuth providers
-- [ ] Add monitoring for security_events table
-- [ ] Consider dropping password_hash column from users table after verification
-- [ ] Back up database before dropping any columns
-- ============================================================================

-- To rollback this migration (CAUTION - will lose new data):
-- DROP TABLE IF EXISTS rate_limits CASCADE;
-- DROP TABLE IF EXISTS trusted_devices CASCADE;
-- DROP TABLE IF EXISTS api_keys CASCADE;
-- DROP TABLE IF EXISTS oauth_providers CASCADE;
-- DROP TABLE IF EXISTS security_events CASCADE;
-- DROP TABLE IF EXISTS login_attempts CASCADE;
-- DROP TABLE IF EXISTS verification_tokens CASCADE;
-- DROP TABLE IF EXISTS two_factor_auth CASCADE;
-- DROP TABLE IF EXISTS user_sessions CASCADE;
-- DROP TABLE IF EXISTS user_credentials CASCADE;
-- ALTER TABLE users DROP COLUMN IF EXISTS email_verified, phone_verified, two_factor_enabled, account_locked, locked_until, locked_reason;
-- DROP VIEW IF EXISTS security_dashboard;
-- DROP VIEW IF EXISTS recent_failed_logins;
-- DROP VIEW IF EXISTS active_sessions_view;
-- DROP FUNCTION IF EXISTS cleanup_expired_sessions();
-- DROP FUNCTION IF EXISTS cleanup_old_verification_tokens();
-- DROP FUNCTION IF EXISTS update_session_activity(UUID);
-- DROP FUNCTION IF EXISTS update_updated_at_column();
