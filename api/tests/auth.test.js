/**
 * Authentication API Tests
 */

const { createClient } = require('@supabase/supabase-js');
const config = require('../config/supabase.config');

// Initialize Supabase client
const supabase = createClient(
  config.supabase.url,
  config.supabase.anonKey
);

describe('Authentication API', () => {
  let testUser = {
    email: 'test' + Date.now() + '@example.com',
    username: 'testuser' + Date.now(),
    password: 'TestPassword123!',
    first_name: 'Test',
    last_name: 'User',
  };

  let sessionToken;
  let refreshToken;
  let userId;

  describe('POST /rpc/register_user', () => {
    test('should register a new user', async () => {
      const { data, error } = await supabase.rpc('register_user', testUser);

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.user_id).toBeDefined();
      expect(data.verification_token).toBeDefined();
      expect(data.message).toContain('successful');

      userId = data.user_id;
    });

    test('should reject duplicate email', async () => {
      const { data, error } = await supabase.rpc('register_user', testUser);

      expect(error).toBeDefined();
      expect(error.message).toContain('already registered');
    });

    test('should reject duplicate username', async () => {
      const duplicateUser = {
        ...testUser,
        email: 'different' + Date.now() + '@example.com',
      };

      const { data, error } = await supabase.rpc('register_user', duplicateUser);

      expect(error).toBeDefined();
      expect(error.message).toContain('already taken');
    });

    test('should validate email format', async () => {
      const invalidUser = {
        ...testUser,
        email: 'invalid-email',
        username: 'unique' + Date.now(),
      };

      const { data, error } = await supabase.rpc('register_user', invalidUser);

      expect(error).toBeDefined();
    });
  });

  describe('POST /rpc/login', () => {
    beforeAll(async () => {
      // First verify the test user
      // In real scenario, this would be done via email verification
      await supabase
        .from('users')
        .update({ is_verified: true })
        .eq('id', userId);
    });

    test('should login with valid credentials', async () => {
      const { data, error } = await supabase.rpc('login', {
        email: testUser.email,
        password: testUser.password,
      });

      expect(error).toBeNull();
      expect(data.success).toBe(true);
      expect(data.user).toBeDefined();
      expect(data.user.email).toBe(testUser.email);
      expect(data.session_token).toBeDefined();
      expect(data.refresh_token).toBeDefined();

      sessionToken = data.session_token;
      refreshToken = data.refresh_token;
    });

    test('should reject invalid password', async () => {
      const { data, error } = await supabase.rpc('login', {
        email: testUser.email,
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
      // Make 5 failed login attempts
      for (let i = 0; i < 5; i++) {
        await supabase.rpc('login', {
          email: testUser.email,
          password: 'WrongPassword',
        });
      }

      // Next attempt should show account locked
      const { data, error } = await supabase.rpc('login', {
        email: testUser.email,
        password: testUser.password,
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
      const expiredToken = 'expired-token-hash';
      await supabase
        .from('refresh_tokens')
        .insert({
          user_id: userId,
          token_hash: expiredToken,
          expires_at: new Date(Date.now() - 1000).toISOString(),
        });

      const { data, error } = await supabase.rpc('refresh_token', {
        refresh_token: 'expired-token',
      });

      expect(error).toBeDefined();
      expect(error.message).toContain('Invalid refresh token');
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
        .from('users')
        .select('*')
        .single();

      expect(error).toBeDefined();
    });
  });

  describe('User Profile Operations', () => {
    let newSessionToken;

    beforeAll(async () => {
      // Login again to get new session
      const { data } = await supabase.rpc('login', {
        email: testUser.email,
        password: testUser.password,
      });
      newSessionToken = data.session_token;
    });

    test('should get user profile', async () => {
      const authenticatedSupabase = createClient(
        config.supabase.url,
        config.supabase.anonKey,
        {
          global: {
            headers: {
              Authorization: `Bearer ${newSessionToken}`,
            },
          },
        }
      );

      const { data, error } = await authenticatedSupabase
        .from('user_profiles')
        .select('*')
        .eq('id', userId)
        .single();

      expect(error).toBeNull();
      expect(data.email).toBe(testUser.email);
      expect(data.username).toBe(testUser.username);
    });

    test('should update user profile', async () => {
      const authenticatedSupabase = createClient(
        config.supabase.url,
        config.supabase.anonKey,
        {
          global: {
            headers: {
              Authorization: `Bearer ${newSessionToken}`,
            },
          },
        }
      );

      const { data, error } = await authenticatedSupabase
        .from('users')
        .update({
          first_name: 'Updated',
          last_name: 'Name',
        })
        .eq('id', userId)
        .select()
        .single();

      expect(error).toBeNull();
      expect(data.first_name).toBe('Updated');
      expect(data.last_name).toBe('Name');
    });
  });

  // Cleanup
  afterAll(async () => {
    // Clean up test user
    if (userId) {
      await supabase
        .from('users')
        .delete()
        .eq('id', userId);
    }
  });
});