async function testLogin() {
  const url = 'http://localhost:9003/rpc/login_safe';
  const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE3NTg4Mzg5NjQsImV4cCI6MjA3NDE5ODk2NH0.8H_56dyR3AUPJi44Jgf5O7iuKg12FHmrkZWfLU6zoc0';

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
        'Accept-Profile': 'api',
        'Content-Profile': 'api'
      },
      body: JSON.stringify({
        email: 'admin@dinkhouse.com',
        password: 'DevPassword123!'
      })
    });

    const text = await response.text();
    console.log('Status:', response.status);
    console.log('Response:', text);

    if (response.ok) {
      const data = JSON.parse(text);
      console.log('Success:', data.success);
    }
  } catch (err) {
    console.error('Error:', err);
  }
}

testLogin();