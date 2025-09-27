const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'http://localhost:9000';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: { persistSession: false }
});

async function createTestPlayer() {
  try {
    console.log('Creating test player account...');

    // Call the player_signup function
    const { data, error } = await supabase
      .schema('api')
      .rpc('player_signup', {
        p_email: 'john.player@example.com',
        p_password: 'PlayerTest123!',
        p_first_name: 'John',
        p_last_name: 'Player',
        p_display_name: 'John P',
        p_phone: '555-1234'
      });

    if (error) {
      console.error('Error creating player:', error);
      return;
    }

    console.log('Player account created successfully!');
    console.log('Response:', data);

    console.log('\n--- Test Player Credentials ---');
    console.log('Email: john.player@example.com');
    console.log('Password: PlayerTest123!');
    console.log('User Type: player');
    console.log('\nTry logging in with these credentials to see the "Players cannot access" message.');

  } catch (err) {
    console.error('Unexpected error:', err);
  }
}

createTestPlayer();