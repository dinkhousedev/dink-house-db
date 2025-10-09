# Contribution Thank You Email API

API endpoints for sending contribution thank you emails with receipts and benefits.

## Base URL

```
http://localhost:3000/api/contribution-emails
```

(or your deployed API URL)

## Endpoints

### 1. Send Thank You Email

Send a contribution thank you email for a specific contribution.

**Endpoint:** `POST /send-thank-you`

**Request Body:**
```json
{
  "contribution_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Contribution thank you email sent successfully",
  "email_log_id": "660e8400-e29b-41d4-a716-446655440000",
  "recipient": "john@example.com",
  "messageId": "<abc123@mail.example.com>"
}
```

**Error Responses:**

400 - Missing contribution_id:
```json
{
  "success": false,
  "error": "contribution_id is required"
}
```

500 - Failed to send:
```json
{
  "success": false,
  "error": "Failed to send email",
  "details": "SMTP connection failed"
}
```

**Usage Example:**
```javascript
// Node.js / JavaScript
const response = await fetch('http://localhost:3000/api/contribution-emails/send-thank-you', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    contribution_id: '550e8400-e29b-41d4-a716-446655440000'
  })
});

const result = await response.json();
console.log(result);
```

```bash
# cURL
curl -X POST http://localhost:3000/api/contribution-emails/send-thank-you \
  -H "Content-Type: application/json" \
  -d '{"contribution_id": "550e8400-e29b-41d4-a716-446655440000"}'
```

---

### 2. Process Pending Emails

Process all pending contribution thank you emails in the queue.

**Endpoint:** `POST /process-pending`

**Request Body:** None (empty body)

**Success Response (200):**
```json
{
  "success": true,
  "message": "Processed 10 pending emails",
  "results": {
    "total": 10,
    "sent": 8,
    "failed": 2,
    "errors": [
      {
        "email_log_id": "770e8400-e29b-41d4-a716-446655440000",
        "error": "Invalid email address"
      },
      {
        "contribution_id": "880e8400-e29b-41d4-a716-446655440000",
        "error": "SMTP timeout"
      }
    ]
  }
}
```

**No Pending Emails (200):**
```json
{
  "success": true,
  "message": "No pending emails to process",
  "processed": 0
}
```

**Usage Example:**
```javascript
// Node.js / JavaScript
const response = await fetch('http://localhost:3000/api/contribution-emails/process-pending', {
  method: 'POST'
});

const result = await response.json();
console.log(`Sent: ${result.results.sent}, Failed: ${result.results.failed}`);
```

```bash
# cURL
curl -X POST http://localhost:3000/api/contribution-emails/process-pending
```

**Scheduling with Cron:**
```javascript
// Using node-cron
const cron = require('node-cron');

// Run every 5 minutes
cron.schedule('*/5 * * * *', async () => {
  console.log('Processing pending contribution emails...');
  const response = await fetch('http://localhost:3000/api/contribution-emails/process-pending', {
    method: 'POST'
  });
  const result = await response.json();
  console.log('Processing complete:', result);
});
```

---

### 3. Resend Email (Manual)

Manually resend a contribution thank you email. Useful for customer support.

**Endpoint:** `POST /resend`

**Request Body:**
```json
{
  "contribution_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Success Response (200):**
```json
{
  "success": true,
  "message": "Contribution thank you email sent successfully",
  "email_log_id": "990e8400-e29b-41d4-a716-446655440000",
  "recipient": "john@example.com",
  "messageId": "<def456@mail.example.com>"
}
```

**Error Responses:**

400 - Contribution not completed:
```json
{
  "success": false,
  "error": "Contribution is not completed yet"
}
```

404 - Contribution not found:
```json
{
  "success": false,
  "error": "Contribution not found"
}
```

**Usage Example:**
```javascript
// Customer support dashboard
async function resendThankYouEmail(contributionId) {
  const response = await fetch('http://localhost:3000/api/contribution-emails/resend', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      contribution_id: contributionId
    })
  });

  const result = await response.json();

  if (result.success) {
    alert('Email resent successfully!');
  } else {
    alert(`Failed: ${result.error}`);
  }
}
```

---

## Integration Guide

### 1. Add to Express App

In your main Express server file (e.g., `api/server.js`):

```javascript
const contributionEmailRoutes = require('./routes/contribution-emails');

// Add the routes
app.use('/api/contribution-emails', contributionEmailRoutes);
```

### 2. Stripe Webhook Integration

Call the send-thank-you endpoint after successful payment:

```javascript
// In your Stripe webhook handler
app.post('/webhooks/stripe', async (req, res) => {
  const event = req.body;

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    const contributionId = session.metadata.contribution_id;

    // Complete the contribution in database
    await completeContribution(contributionId);

    // Send thank you email
    await fetch('http://localhost:3000/api/contribution-emails/send-thank-you', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contribution_id: contributionId })
    });
  }

  res.json({ received: true });
});
```

### 3. Automated Email Processing

Set up a scheduled job to process pending emails:

```javascript
// jobs/email-processor.js
const cron = require('node-cron');
const fetch = require('node-fetch');

// Process pending emails every 5 minutes
cron.schedule('*/5 * * * *', async () => {
  try {
    console.log('[Email Processor] Starting...');

    const response = await fetch('http://localhost:3000/api/contribution-emails/process-pending', {
      method: 'POST'
    });

    const result = await response.json();

    console.log(`[Email Processor] Sent: ${result.results?.sent || 0}, Failed: ${result.results?.failed || 0}`);
  } catch (error) {
    console.error('[Email Processor] Error:', error);
  }
});

console.log('[Email Processor] Scheduled to run every 5 minutes');
```

---

## Database Triggers

The database automatically queues emails when contributions are completed. The trigger:

1. Allocates benefits from the tier
2. Prepares email data
3. Creates a log entry in `system.email_logs` with status 'pending'

Then your API can:
- Process pending emails automatically (recommended)
- Send emails immediately via webhook (faster, but requires API to be running)

---

## Email Log Statuses

Emails in `system.email_logs` can have these statuses:

- **pending**: Queued, waiting to be sent
- **sent**: Successfully delivered
- **failed**: Send attempt failed (check `error_message`)
- **opened**: Recipient opened the email (if tracking enabled)
- **clicked**: Recipient clicked a link (if tracking enabled)

---

## Monitoring & Troubleshooting

### Check Pending Emails

```sql
SELECT id, to_email, created_at, metadata
FROM system.email_logs
WHERE template_key = 'contribution_thank_you'
  AND status = 'pending'
ORDER BY created_at;
```

### Check Failed Emails

```sql
SELECT id, to_email, error_message, created_at
FROM system.email_logs
WHERE template_key = 'contribution_thank_you'
  AND status = 'failed'
ORDER BY created_at DESC;
```

### Check Email Sent Status

```sql
SELECT
  status,
  COUNT(*) as count
FROM system.email_logs
WHERE template_key = 'contribution_thank_you'
GROUP BY status;
```

### Retry Failed Email

```bash
curl -X POST http://localhost:3000/api/contribution-emails/resend \
  -H "Content-Type: application/json" \
  -d '{"contribution_id": "contribution-uuid-here"}'
```

---

## Security Considerations

1. **Authentication**: Add authentication middleware to protect endpoints
2. **Rate Limiting**: Implement rate limiting to prevent abuse
3. **Validation**: Validate UUIDs and sanitize inputs
4. **Logging**: Log all email operations for audit trail
5. **Error Handling**: Never expose sensitive information in error messages

### Example with Authentication

```javascript
const { authenticateAdmin } = require('../middleware/auth');

router.post('/resend', authenticateAdmin, async (req, res) => {
  // Only authenticated admins can manually resend emails
  // ... rest of handler
});
```

---

## Testing

### Test Email Send

```bash
# 1. Create a test contribution (in database)
# 2. Send test email
curl -X POST http://localhost:3000/api/contribution-emails/send-thank-you \
  -H "Content-Type: application/json" \
  -d '{"contribution_id": "YOUR_TEST_CONTRIBUTION_ID"}'
```

### Test Pending Email Processing

```bash
# Process any pending emails
curl -X POST http://localhost:3000/api/contribution-emails/process-pending
```

---

## Support

For issues or questions:
- Check API logs for detailed error messages
- Review `system.email_logs` table for email status
- Verify email configuration in `api/config/supabase.config.js`
- Contact development team
