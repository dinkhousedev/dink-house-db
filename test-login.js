const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'http://localhost:9003';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE3NTg4Mzg5NjQsImV4cCI6MjA3NDE5ODk2NH0.8H_56dyR3AUPJi44Jgf5O7iuKg12FHmrkZWfLU6zoc0';

const supabase = createClient(supabaseUrl, serviceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

async function testLogin() {
  try {
    console.log('Testing login_safe RPC...');
    const { data, error } = await supabase.rpc('login_safe', {
      email: 'admin@dinkhouse.com',
      password: 'DevPassword123!'
    });

    if (error) {
      console.error('RPC Error:', error);
    } else {
      console.log('RPC Success:', JSON.stringify(data, null, 2));
    }
  } catch (err) {
    console.error('Caught error:', err);
  }
}

testLogin();