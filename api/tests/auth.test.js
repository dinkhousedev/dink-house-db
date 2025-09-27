/**
 * Authentication API Tests
 */

const crypto = require('crypto');
const { createClient } = require('@supabase/supabase-js');
const config = require('../config/supabase.config');

// Initialize Supabase client
const supabase = createClient(
  config.supabase.url,
  config.supabase.serviceKey
);

describe('Authentication API', () => {
  const playerUser = {
    email: 'player' + Date.now() + '@example.com',
    password: 'TestPassword123!',
    first_name: 'Test',
    last_name: 'Player',
  };

  let sessionToken;
  let refreshToken;
  let accountId;

  describe('POST /rpc/player_signup', () => {
    test('should register a new player', async () => {
      const { data, error } = await supabase.rpc('player_signup', playerUser);

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.user_id).toBeDefined();
      expect(data.user_type).toBe('player');
      expect(data.message).toContain('Registration successful');

      accountId = data.user_id;
    });

    test('should reject duplicate email', async () => {
      const { data, error } = await supabase.rpc('player_signup', playerUser);

      expect(error).toBeDefined();
      expect(error.message).toContain('already registered');
    });

    test('should validate email format', async () => {
      const invalidUser = {
        ...playerUser,
        email: 'invalid-email',
      };

      const { data, error } = await supabase.rpc('player_signup', invalidUser);

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid email');
    });
  });

  describe('POST /rpc/login', () => {
    test('should login with valid credentials', async () => {
      const { data, error } = await supabase.rpc('login', {
        email: playerUser.email,
        password: playerUser.password,
      });

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.user).toBeDefined();
      expect(data.user.email).toBe(playerUser.email);
      expect(data.user.account_id).toBe(accountId);
      expect(data.user.user_type).toBe('player');
      expect(data.session_token).toBeDefined();
      expect(data.refresh_token).toBeDefined();

      sessionToken = data.session_token;
      refreshToken = data.refresh_token;
    });

    test('should reject invalid password', async () => {
      const { data, error } = await supabase.rpc('login', {
        email: playerUser.email,
        password: 'WrongPassword123!',
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid credentials');
    });

    test('should reject non-existent user', async () => {
      const { data, error } = await supabase.rpc('login', {
        email: 'nonexistent@example.com',
        password: 'Password123!',
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid credentials');
    });

    test('should lock account after multiple failed attempts', async () => {
      const tempUser = {
        email: global.testUtils.generateRandomEmail(),
        password: 'TempPassword123!',
        first_name: 'Temp',
        last_name: 'User',
      };

      const { data: signup } = await supabase.rpc('player_signup', tempUser);
      expect(signup.success).toBe(true);

      for (let i = 0; i < 5; i++) {
        await supabase.rpc('login', {
          email: tempUser.email,
          password: 'WrongPassword',
        });
      }

      const { error } = await supabase.rpc('login', {
        email: tempUser.email,
        password: tempUser.password,
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('locked');
    });
  });

  describe('POST /rpc/refresh_token', () => {
    test('should refresh access token', async () => {
      const { data, error } = await supabase.rpc('refresh_token', {
        refresh_token: refreshToken,
      });

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.session_token).toBeDefined();
      expect(data.refresh_token).toBeDefined();
      expect(data.session_token).not.toBe(sessionToken);

      // Update tokens for next tests
      sessionToken = data.session_token;
      refreshToken = data.refresh_token;
    });

    test('should reject invalid refresh token', async () => {
      const { data, error } = await supabase.rpc('refresh_token', {
        refresh_token: 'invalid-token',
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid refresh token');
    });

    test('should reject expired refresh token', async () => {
      // Create an expired token in the database for testing
      const expiredToken = 'expired-token';
      const expiredTokenHash = crypto
        .createHash('sha256')
        .update(expiredToken)
        .digest('hex');

      await supabase
        .from('app_auth_refresh_tokens')
        .insert({
          account_id: accountId,
          user_type: 'player',
          token_hash: expiredTokenHash,
          expires_at: new Date(Date.now() - 1000).toISOString(),
        });

      const { data, error } = await supabase.rpc('refresh_token', {
        refresh_token: expiredToken,
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid refresh token');
    });
  });

  describe('POST /rpc/guest_check_in', () => {
    test('should create a guest profile with session tokens', async () => {
      const guestPayload = {
        display_name: 'Walk-in Guest',
        email: `guest.${Date.now()}@example.com`,
        phone: '555-123-4567',
      };

      const { data, error } = await supabase.rpc('guest_check_in', guestPayload);

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.user_type).toBe('guest');
      expect(data.session_token).toBeDefined();
      expect(data.refresh_token).toBeDefined();
      expect(data.guest.display_name).toBe(guestPayload.display_name);
      expect(data.guest.email).toBe(guestPayload.email.toLowerCase());
    });
  });

  describe('POST /rpc/logout', () => {
    test('should logout successfully', async () => {
      const { data, error } = await supabase.rpc('logout', {
        session_token: sessionToken,
      });

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.message).toContain('Logged out');
    });

    test('should reject invalid session token', async () => {
      const { data, error } = await supabase.rpc('logout', {
        session_token: 'invalid-token',
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid session');
    });

    test('should not allow using session after logout', async () => {
      // Try to use the old session token
      const authenticatedSupabase = createClient(
        config.supabase.url,
        config.supabase.anonKey,
        {
          global: {
            headers: {
              Authorization: `Bearer ${sessionToken}`,
            },
          },
        }
      );

      const { data, error } = await authenticatedSupabase
        .from('app_auth_user_accounts')
        .select('*')
        .single();

      expect(error).toBeDefined();
    });
  });
  
  afterAll(async () => {
    if (accountId) {
      await supabase
        .from('app_auth_user_accounts')
        .delete()
        .eq('id', accountId);
    }
  });
});
