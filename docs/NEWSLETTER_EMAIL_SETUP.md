# Newsletter Email Integration

This document explains how newsletter signups trigger welcome emails via SendGrid.

## Overview

When a user signs up for the newsletter through the landing page, the system:
1. Stores the subscriber in `launch.launch_subscribers`
2. Creates a contact inquiry record
3. Queues a welcome email via database trigger
4. Processes the email queue asynchronously via Edge Function

## Architecture

### Database Components

1. **Email Template** (`system.email_templates`)
   - Template key: `newsletter_welcome`
   - Branded HTML email with Dink House styling
   - Variables: `first_name`, `email`, `site_url`, `logo_url`

2. **Email Queue** (`launch.newsletter_email_queue`)
   - Stores pending newsletter welcome emails
   - Status: `pending` | `sent` | `failed`
   - Automatically populated via database trigger

3. **Database Trigger** (`on_newsletter_signup`)
   - Fires on `INSERT` to `launch.launch_subscribers`
   - Queues email in `newsletter_email_queue`
   - Non-blocking (doesn't delay signup response)

### Edge Functions

1. **send-email-sendgrid** (`/functions/v1/send-email-sendgrid`)
   - Handles all SendGrid email sending
   - Supports email templates with variable substitution
   - Logs emails to `system.email_logs`

2. **process-newsletter-emails** (`/functions/v1/process-newsletter-emails`)
   - Processes pending emails from queue
   - Batches up to 50 emails per run
   - Updates queue status (sent/failed)
   - Can be triggered via cron or webhook

## Setup Instructions

### 1. Run Database Migrations

```bash
cd dink-house-db
supabase db push
```

Or run migrations manually in Supabase Studio:
- `00006_newsletter_email_integration.sql` - Creates template and queue
- `00007_newsletter_webhook_integration.sql` - Adds webhook support

### 2. Deploy Edge Functions

```bash
# Deploy SendGrid email function (if not already deployed)
supabase functions deploy send-email-sendgrid

# Deploy newsletter email processor
supabase functions deploy process-newsletter-emails
```

### 3. Set Environment Variables

Ensure these are set in Supabase Dashboard > Settings > Edge Functions:

```env
SENDGRID_API_KEY=SG.xxxxxxxxxxxxx
EMAIL_FROM=hello@dinkhousepb.com
EMAIL_REPLY_TO=support@dinkhousepb.com
SITE_URL=https://dinkhousepb.com
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=xxxxxxxxxxxxx
```

### 4. Set Up Cron Job (Recommended)

Create a cron job to process the email queue automatically:

**In Supabase Dashboard > Database > Cron Jobs:**

```sql
-- Process newsletter emails every minute
SELECT cron.schedule(
    'process-newsletter-emails',
    '* * * * *', -- Every minute
    $$
    SELECT net.http_post(
        url := current_setting('app.supabase_url') || '/functions/v1/process-newsletter-emails',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key')
        ),
        body := '{}'::jsonb
    );
    $$
);
```

**Alternative: Use pg_cron extension**

```sql
-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule email processing every minute
SELECT cron.schedule(
    'process-newsletter-emails-queue',
    '* * * * *',
    'SELECT process_newsletter_email_queue();'
);
```

### 5. Manual Processing (Development/Testing)

You can manually trigger email processing:

```bash
# Via curl
curl -X POST https://your-project.supabase.co/functions/v1/process-newsletter-emails \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json"

# Via Supabase CLI
supabase functions invoke process-newsletter-emails --no-verify-jwt
```

## Testing

### 1. Test Newsletter Signup

```bash
# Test via API
curl -X POST https://api.dinkhousepb.com/rest/v1/rpc/submit_newsletter_signup \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR_ANON_KEY" \
  -d '{
    "p_email": "test@example.com",
    "p_first_name": "Test",
    "p_last_name": "User"
  }'
```

### 2. Check Email Queue

```sql
-- View pending emails
SELECT * FROM launch.newsletter_email_queue
WHERE status = 'pending'
ORDER BY created_at DESC;

-- View sent emails
SELECT * FROM launch.newsletter_email_queue
WHERE status = 'sent'
ORDER BY sent_at DESC
LIMIT 10;

-- View failed emails
SELECT * FROM launch.newsletter_email_queue
WHERE status = 'failed'
ORDER BY created_at DESC;
```

### 3. Check Email Logs

```sql
-- View recent newsletter emails
SELECT
    el.*,
    eq.status as queue_status
FROM system.email_logs el
LEFT JOIN launch.newsletter_email_queue eq ON el.to_email = eq.email
WHERE el.template_key = 'newsletter_welcome'
ORDER BY el.created_at DESC
LIMIT 20;
```

### 4. Manually Process Queue

```sql
-- Process a specific email from queue (for testing)
SELECT process_newsletter_email_queue();
```

## Monitoring

### Check Queue Health

```sql
-- Count by status
SELECT status, COUNT(*)
FROM launch.newsletter_email_queue
GROUP BY status;

-- Old pending emails (might indicate issue)
SELECT *
FROM launch.newsletter_email_queue
WHERE status = 'pending'
AND created_at < NOW() - INTERVAL '1 hour';
```

### Email Success Rate

```sql
-- Newsletter email success rate (last 7 days)
SELECT
    DATE(created_at) as date,
    COUNT(*) as total_sent,
    SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM launch.newsletter_email_queue
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

## Troubleshooting

### Emails Not Sending

1. **Check queue**: `SELECT * FROM launch.newsletter_email_queue WHERE status = 'pending'`
2. **Check SendGrid API key**: Verify in Supabase Edge Function secrets
3. **Check Edge Function logs**: Supabase Dashboard > Functions > process-newsletter-emails > Logs
4. **Manually trigger processor**: See "Manual Processing" above

### Emails Marked as Failed

```sql
-- View error messages
SELECT email, error_message, created_at
FROM launch.newsletter_email_queue
WHERE status = 'failed'
ORDER BY created_at DESC;
```

Common issues:
- Invalid SendGrid API key
- Email template not found
- SendGrid rate limits
- Invalid recipient email address

### Reset Failed Emails

```sql
-- Retry failed emails (resets to pending)
UPDATE launch.newsletter_email_queue
SET status = 'pending', error_message = NULL
WHERE status = 'failed'
AND created_at > NOW() - INTERVAL '24 hours';
```

## Email Template Customization

To modify the welcome email template:

```sql
-- Update template in database
UPDATE system.email_templates
SET
    subject = 'Your Custom Subject',
    html_body = 'Your HTML content with {{first_name}} variables',
    text_body = 'Your plain text version',
    updated_at = CURRENT_TIMESTAMP
WHERE template_key = 'newsletter_welcome';
```

Variables available:
- `{{first_name}}` - Subscriber's first name
- `{{email}}` - Subscriber's email
- `{{site_url}}` - Site URL (e.g., https://dinkhousepb.com)
- `{{logo_url}}` - Logo image URL

## Performance Considerations

- **Queue Processing**: Batches 50 emails per run (adjustable)
- **Cron Frequency**: Every 1 minute (adjustable based on volume)
- **SendGrid Limits**: 100 emails/second (Free tier), adjust accordingly
- **Database Indexes**: Already optimized on `status` and `created_at`

## Security

- Queue table uses RLS (Row Level Security)
- Only service role can process queue
- Email function requires authentication
- No sensitive data stored in queue (passwords, etc.)

## Future Enhancements

1. **Double Opt-In**: Add email verification before sending newsletter
2. **Unsubscribe Links**: Add unsubscribe functionality to emails
3. **Email Analytics**: Track opens, clicks via SendGrid webhooks
4. **Retry Logic**: Exponential backoff for failed emails
5. **Priority Queue**: High-priority emails processed first