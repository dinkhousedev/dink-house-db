/**
 * Test Setup
 * Initialize test environment
 */

require('dotenv').config({ path: '../../.env.local' });

// Set test environment variables
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = process.env.SUPABASE_URL || 'http://localhost:9002';
process.env.SUPABASE_ANON_KEY = process.env.ANON_KEY;
process.env.SUPABASE_SERVICE_KEY = process.env.SERVICE_KEY;

// Global test utilities
global.testUtils = {
  generateRandomEmail: () => `test${Date.now()}${Math.random().toString(36).substring(7)}@example.com`,
  generateRandomUsername: () => `user${Date.now()}${Math.random().toString(36).substring(7)}`,
  generateRandomString: (length = 10) => Math.random().toString(36).substring(2, length + 2),

  sleep: (ms) => new Promise(resolve => setTimeout(resolve, ms)),

  createTestUser: async (supabase, overrides = {}) => {
    const userData = {
      email: global.testUtils.generateRandomEmail(),
      username: global.testUtils.generateRandomUsername(),
      password: 'TestPassword123!',
      first_name: 'Test',
      last_name: 'User',
      ...overrides,
    };

    const { data, error } = await supabase.rpc('register_user', userData);

    if (error) throw error;

    // Auto-verify for testing
    await supabase
      .from('users')
      .update({ is_verified: true })
      .eq('id', data.user_id);

    return { ...userData, id: data.user_id };
  },

  cleanupTestUser: async (supabase, userId) => {
    if (userId) {
      await supabase
        .from('users')
        .delete()
        .eq('id', userId);
    }
  },

  loginTestUser: async (supabase, email, password) => {
    const { data, error } = await supabase.rpc('login', {
      email,
      password,
    });

    if (error) throw error;

    return data;
  },

  createAuthenticatedClient: (supabase, token) => {
    const { createClient } = require('@supabase/supabase-js');

    return createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY,
      {
        global: {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
      }
    );
  },
};

// Setup test database connection check
beforeAll(async () => {
  const { createClient } = require('@supabase/supabase-js');

  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY
  );

  // Check database connection
  try {
    const { error } = await supabase
      .from('users')
      .select('count')
      .limit(1);

    if (error) {
      console.error('Database connection failed:', error);
      process.exit(1);
    }
  } catch (err) {
    console.error('Failed to connect to database:', err);
    process.exit(1);
  }
});

// Global error handler
process.on('unhandledRejection', (err) => {
  console.error('Unhandled rejection:', err);
  process.exit(1);
});