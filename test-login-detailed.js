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
    console.log('Testing direct PostgREST call...');

    // Try the raw fetch to PostgREST
    const response = await fetch('http://localhost:9003/rpc/login_safe', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`
      },
      body: JSON.stringify({
        email: 'admin@dinkhouse.com',
        password: 'DevPassword123!'
      })
    });

    const responseText = await response.text();
    console.log('Response status:', response.status);
    console.log('Response headers:', Object.fromEntries(response.headers.entries()));
    console.log('Response body:', responseText);

    try {
      const data = JSON.parse(responseText);
      console.log('Parsed response:', JSON.stringify(data, null, 2));
    } catch (e) {
      console.log('Could not parse as JSON');
    }
  } catch (err) {
    console.error('Caught error:', err);
  }
}

testLogin();