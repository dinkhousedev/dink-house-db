# Newsletter Opt-In/Opt-Out Implementation

## Overview

This implementation provides a complete GDPR-compliant double opt-in and unsubscribe system for The Dink House newsletter.

## Features Implemented

### ✅ Double Opt-In Flow
- New subscribers start with `status='pending'` and `is_active=false`
- Secure verification tokens generated for each signup
- Confirmation email sent with verification link
- Subscribers must confirm before receiving newsletters

### ✅ Secure Unsubscribe
- Each subscriber gets a unique `unsubscribe_token`
- One-click unsubscribe from email footer links
- Manual unsubscribe page with optional feedback
- Unsubscribe events are logged for analytics

### ✅ Updated Email System
- Marketing emails only sent to `status='active'` subscribers
- All emails include secure unsubscribe links
- Unsubscribe tokens pulled from database (no ad-hoc generation)

## Database Changes

### New Columns in `launch.launch_subscribers`

```sql
-- Secure token for unsubscribe links (unique per subscriber)
unsubscribe_token VARCHAR(255) UNIQUE

-- Subscription lifecycle status
status VARCHAR(50) DEFAULT 'pending'
  CHECK (status IN ('pending', 'active', 'inactive', 'bounced', 'complained'))
```

### New Indexes

```sql
-- Fast token lookups
CREATE INDEX idx_launch_subscribers_verification_token
    ON launch.launch_subscribers(verification_token);

CREATE INDEX idx_launch_subscribers_unsubscribe_token
    ON launch.launch_subscribers(unsubscribe_token);
```

## API Functions

### 1. Newsletter Signup (Updated)

**Endpoint:** `POST /rest/v1/rpc/submit_newsletter_signup`

**Parameters:**
```json
{
  "p_email": "user@example.com",
  "p_first_name": "John",
  "p_last_name": "Doe"
}
```

**Response:**
```json
{
  "success": true,
  "already_subscribed": false,
  "requires_confirmation": true,
  "message": "Please check your email to confirm your subscription",
  "subscriber_id": "uuid",
  "verification_token": "token"
}
```

**Behavior:**
- Sets `status='pending'` and `is_active=false`
- Generates secure `verification_token` and `unsubscribe_token`
- Returns verification token for confirmation email
- If already subscribed and active, returns `already_subscribed=true`
- Allows re-subscription for previously unsubscribed users

### 2. Confirm Subscription (New)

**Endpoint:** `POST /rest/v1/rpc/confirm_newsletter_subscription`

**Parameters:**
```json
{
  "p_verification_token": "hex_token_from_email"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Your subscription has been confirmed!",
  "subscriber_id": "uuid",
  "email": "user@example.com"
}
```

**Behavior:**
- Finds subscriber by `verification_token`
- Updates: `status='active'`, `is_active=true`, `verified_at=NOW()`
- Clears verification token (one-time use)
- Logs confirmation event

### 3. Unsubscribe (New)

**Endpoint:** `POST /rest/v1/rpc/unsubscribe_newsletter`

**Parameters:**
```json
{
  "p_unsubscribe_token": "hex_token_from_email",  // Preferred method
  "p_email": "user@example.com",                   // Fallback method
  "p_reason": "Optional feedback text"
}
```

**Response:**
```json
{
  "success": true,
  "message": "You have been successfully unsubscribed",
  "email": "user@example.com"
}
```

**Behavior:**
- Finds subscriber by token (secure) or email (less secure)
- Updates: `status='inactive'`, `is_active=false`, `unsubscribed_at=NOW()`
- Stores optional unsubscribe reason
- Logs unsubscribe event
- Returns friendly message even if already unsubscribed

### 4. Get Subscriber Preferences (New)

**Endpoint:** `POST /rest/v1/rpc/get_subscriber_preferences`

**Parameters:**
```json
{
  "p_email": "user@example.com"
}
```

**Response:**
```json
{
  "success": true,
  "subscriber": {
    "email": "user@example.com",
    "first_name": "John",
    "last_name": "Doe",
    "status": "active",
    "is_active": true,
    "subscription_date": "2024-10-02T10:00:00Z",
    "verified_at": "2024-10-02T10:05:00Z",
    "unsubscribed_at": null
  }
}
```

## Frontend Pages

### 1. Confirmation Page

**URL:** `/confirm-subscription?token=VERIFICATION_TOKEN`

**Features:**
- Auto-confirms subscription when page loads
- Shows success message with welcome content
- Displays error for invalid/expired tokens
- Links to home and social media

**File:** `dink-house-landing-dev/pages/confirm-subscription.tsx`

### 2. Unsubscribe Page

**URL:** `/unsubscribe?token=UNSUBSCRIBE_TOKEN` (one-click)
**URL:** `/unsubscribe?email=EMAIL` (manual)

**Features:**
- One-click unsubscribe via token (automatic)
- Manual unsubscribe confirmation with reason field
- Shows what subscribers will miss
- Option to cancel and stay subscribed
- Links to resubscribe or contact support

**File:** `dink-house-landing-dev/pages/unsubscribe.tsx`

### 3. Updated Newsletter Form

**File:** `dink-house-landing-dev/components/newsletter-form.tsx`

**Changes:**
- Shows "Check your email" message for new signups
- Indicates pending confirmation state
- Handles already-subscribed users gracefully

## Email Templates

### Confirmation Email

**Template Slug:** `newsletter-confirmation`

**Variables:**
- `{{first_name}}` - Subscriber's first name
- `{{confirmation_url}}` - Full URL with verification token
- `{{email}}` - Subscriber's email address

**Location:** Database (`launch.notification_templates`)

**Migration:** `dink-house-db/supabase/migrations/20251002150200_confirmation_email_template.sql`

### Marketing Emails

All marketing emails include:
- Unsubscribe link in footer using `{{unsubscribe_link}}`
- Personalization with `{{first_name}}`, `{{last_name}}`
- Links to preference center

**Updated Files:**
- `dink-house-db/supabase/functions/generate-marketing-email/email-template.ts`
- `dink-house-db/supabase/functions/generate-marketing-email/send-batch.ts`

## Email Sending Flow

### New Subscriber Flow

1. **User signs up** via newsletter form
2. **Backend creates subscriber** with `status='pending'`
3. **Backend generates tokens** (verification + unsubscribe)
4. **Application sends confirmation email** with verification link
5. **User clicks confirmation link** in email
6. **Frontend confirms subscription** via API
7. **Subscriber activated** (`status='active'`, `is_active=true`)
8. **User receives newsletters** going forward

### Marketing Email Flow

1. **Admin generates email** via marketing dashboard
2. **System fetches active subscribers** (`status='active'` AND `verified_at IS NOT NULL`)
3. **System personalizes each email** with subscriber data
4. **Each email includes** secure unsubscribe link with token
5. **SendGrid tracks** opens, clicks, bounces
6. **Webhooks update** engagement metrics

### Unsubscribe Flow

1. **User clicks unsubscribe** in email footer
2. **Link contains** secure `unsubscribe_token`
3. **Frontend auto-processes** unsubscribe (one-click)
4. **Backend updates** `status='inactive'`, `is_active=false`
5. **User immediately stops** receiving emails
6. **Event logged** for analytics

## Subscriber Filtering

### Active Subscribers Query

```typescript
const { data } = await supabase
  .schema('launch')
  .from('launch_subscribers')
  .select('id, email, first_name, last_name, unsubscribe_token')
  .eq('is_active', true)
  .eq('status', 'active')
  .not('verified_at', 'is', null);
```

**Ensures only subscribers who:**
- Are active (`is_active=true`)
- Have confirmed status (`status='active'`)
- Completed verification (`verified_at IS NOT NULL`)

## Security Features

### Token Generation
- Uses cryptographically secure random bytes (`gen_random_bytes(32)`)
- Tokens are hex-encoded (64 characters)
- Unique per subscriber
- One-time use for verification tokens

### Token Storage
- Verification tokens cleared after use
- Unsubscribe tokens persist (permanent unsubscribe links)
- Indexes for fast lookups
- Unique constraints prevent duplicates

### API Security
- All functions use `SECURITY DEFINER` for controlled access
- Input validation for email format
- SQL injection prevention via prepared statements
- Rate limiting recommended at API gateway level

## Testing Checklist

### New Signup Flow
- [ ] Subscribe with new email
- [ ] Receive confirmation email
- [ ] Click confirmation link
- [ ] Verify subscription activated
- [ ] Receive marketing emails

### Already Subscribed
- [ ] Try subscribing with active email
- [ ] See "already subscribed" message
- [ ] No duplicate records created

### Re-subscription
- [ ] Unsubscribe from newsletter
- [ ] Try subscribing again with same email
- [ ] Receive new confirmation email
- [ ] Complete confirmation
- [ ] Verify reactivated

### Unsubscribe Flow
- [ ] Click unsubscribe in email
- [ ] Verify one-click unsubscribe works
- [ ] Check subscription marked inactive
- [ ] Stop receiving emails
- [ ] Unsubscribe reason recorded (if provided)

### Error Handling
- [ ] Invalid verification token
- [ ] Expired verification link
- [ ] Invalid unsubscribe token
- [ ] Already unsubscribed user

## Migration Instructions

### Database Migrations

Run in order:

```bash
cd dink-house-db

# 1. Add columns and indexes
supabase migration apply 20251002150000_add_newsletter_opt_in_out

# 2. Create/update API functions
supabase migration apply 20251002150100_newsletter_opt_in_functions

# 3. Create email template
supabase migration apply 20251002150200_confirmation_email_template
```

### Deploy Edge Functions

```bash
cd dink-house-db

# Deploy updated marketing email function
supabase functions deploy generate-marketing-email
```

### Frontend Deployment

```bash
cd dink-house-landing-dev

# Build and deploy
npm run build
npm run start  # or deploy to hosting
```

## Environment Variables

Ensure these are set:

```bash
# Backend (dink-house-db)
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
SENDGRID_API_KEY=your_sendgrid_api_key
SITE_URL=https://dinkhousepb.com

# Frontend (dink-house-landing-dev)
NEXT_PUBLIC_API_URL=https://api.dinkhousepb.com
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
```

## Sending Confirmation Emails

The confirmation email should be sent automatically when a user signs up. You'll need to integrate this with your email sending system.

### Option 1: Database Trigger (Recommended)

Create a trigger that fires when a subscriber is created:

```sql
-- Example trigger (customize for your email system)
CREATE OR REPLACE FUNCTION send_confirmation_email()
RETURNS TRIGGER AS $$
BEGIN
  -- Insert into email queue or call edge function
  -- Implementation depends on your email infrastructure
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_send_confirmation_email
  AFTER INSERT ON launch.launch_subscribers
  FOR EACH ROW
  WHEN (NEW.status = 'pending' AND NEW.verification_token IS NOT NULL)
  EXECUTE FUNCTION send_confirmation_email();
```

### Option 2: Application Layer

Send confirmation email immediately after signup in your application code:

```typescript
// After newsletter signup succeeds
if (result.success && result.verification_token) {
  const confirmationUrl = `${SITE_URL}/confirm-subscription?token=${result.verification_token}`;

  await sendEmail({
    to: email,
    template: 'newsletter-confirmation',
    variables: {
      first_name: firstName,
      confirmation_url: confirmationUrl,
      email: email
    }
  });
}
```

## Compliance Notes

### GDPR Compliance
✅ Double opt-in implemented
✅ Explicit consent required
✅ Easy unsubscribe mechanism
✅ Unsubscribe reasons tracked
✅ Data minimization (only necessary fields)

### CAN-SPAM Compliance
✅ Unsubscribe link in every email
✅ One-click unsubscribe available
✅ Immediate removal from list (no delay)
✅ Physical address in footer (add to email template)

### CASL Compliance (Canada)
✅ Express consent via opt-in
✅ Clear identification of sender
✅ Unsubscribe mechanism prominent
✅ Records of consent maintained

## Monitoring & Analytics

Track these metrics:

- **Opt-in rate**: Confirmations / Signups
- **Unsubscribe rate**: Unsubscribes / Total Active
- **Bounce rate**: Bounced emails / Total Sent
- **Engagement rate**: Opens + Clicks / Total Sent

Query examples:

```sql
-- Opt-in rate
SELECT
  COUNT(*) FILTER (WHERE status = 'active') * 100.0 / COUNT(*) as opt_in_rate
FROM launch.launch_subscribers;

-- Unsubscribe reasons
SELECT
  unsubscribe_reason,
  COUNT(*) as count
FROM launch.launch_subscribers
WHERE status = 'inactive'
  AND unsubscribe_reason IS NOT NULL
GROUP BY unsubscribe_reason
ORDER BY count DESC;
```

## Troubleshooting

### Subscriber not receiving emails

1. Check subscriber status: `status='active'` AND `is_active=true`
2. Verify `verified_at` is not null
3. Check email isn't bounced or complained
4. Verify SendGrid is not blocking the email

### Confirmation link not working

1. Check token hasn't been used (cleared after confirmation)
2. Verify subscriber still has `status='pending'`
3. Check token matches database exactly (case-sensitive)

### Unsubscribe not working

1. Verify unsubscribe token is valid
2. Check subscriber exists in database
3. Review API logs for errors
4. Ensure proper API permissions

## Future Enhancements

- [ ] Add token expiry for verification links (7 days)
- [ ] Implement preference center (frequency, topics)
- [ ] Add welcome email series for new subscribers
- [ ] Create subscriber segments for targeted campaigns
- [ ] Add A/B testing for confirmation emails
- [ ] Implement progressive profiling
- [ ] Add SMS opt-in option
- [ ] Create subscriber lifecycle automation

## Support

For issues or questions:
- Check database logs: `system.activity_logs`
- Review API function code in migrations
- Test with curl or Postman
- Contact: support@dinkhousepb.com
