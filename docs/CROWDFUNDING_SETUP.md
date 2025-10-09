# Crowdfunding Campaign Setup Guide

Complete implementation guide for the Dink House crowdfunding system with Stripe integration.

## Overview

The crowdfunding system allows supporters to contribute to three campaigns:
1. **Build the Courts** - Main campaign ($75K goal)
2. **Dink Practice Boards** - Equipment campaign ($1.2K goal)
3. **Ball Machine Equipment** - Training equipment ($7K goal)

## Architecture

```
User → Campaign Page → Contribution Modal → Stripe Checkout
                                             ↓
                                        Webhook
                                             ↓
                           Supabase Database Updates
                                             ↓
                                      Founders Wall Display
```

## Database Setup

### 1. Run Schema Migration

Connect to your Supabase database and run the schema:

```bash
cd dink-house-db
psql <connection-string> -f sql/modules/26-crowdfunding-schema.sql
```

Or via Supabase Studio:
1. Go to https://wchxzbuuwssrnaxshseu.supabase.co
2. Navigate to SQL Editor
3. Copy contents of `sql/modules/26-crowdfunding-schema.sql`
4. Execute

### 2. Seed Campaign Data

Run the seed file to populate campaigns and tiers:

```bash
psql <connection-string> -f sql/seeds/crowdfunding-seed.sql
```

Or via Supabase Studio SQL Editor.

### 3. Verify Tables

Check that tables were created in the `crowdfunding` schema:
- `backers`
- `campaign_types`
- `contribution_tiers`
- `contributions`
- `backer_benefits`
- `court_sponsors`
- `founders_wall`

## Stripe Configuration

### 1. Create Stripe Account

If you haven't already:
1. Go to https://stripe.com
2. Sign up for an account
3. Activate your account

### 2. Get API Keys

**Test Mode** (for development):
1. In Stripe Dashboard, ensure "Test mode" toggle is ON
2. Go to Developers → API Keys
3. Copy:
   - **Publishable key** (starts with `pk_test_`)
   - **Secret key** (starts with `sk_test_`)

**Live Mode** (for production):
1. Complete Stripe account activation
2. Toggle "Test mode" OFF
3. Get live keys (start with `pk_live_` and `sk_live_`)

### 3. Update Environment Variables

Edit `dink-house-landing/.env.local`:

```bash
# Replace these with your actual Stripe keys
STRIPE_SECRET_KEY=sk_test_YOUR_SECRET_KEY_HERE
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_YOUR_PUBLISHABLE_KEY_HERE
STRIPE_WEBHOOK_SECRET=whsec_YOUR_WEBHOOK_SECRET_HERE
```

**IMPORTANT**: You provided the publishable key `pk_test_51SBgorQ4M7SOiop2MZVKL5Duoad0OwEi4weFYR8W5Vg6YzqcTcX4Ztmk7Y0rjI06xZKFGNwkFbwJJopgJq88uEdT00KtlYiPkP`. You need to:
1. Get the corresponding **secret key** from your Stripe Dashboard
2. Get the **webhook secret** after setting up the webhook (see below)

### 4. Get Supabase Service Role Key

The `SUPABASE_SERVICE_KEY` in `.env.local` is currently set to `your-service-key-here`. Update it:

1. Go to https://wchxzbuuwssrnaxshseu.supabase.co
2. Settings → API
3. Copy the `service_role` key (starts with `eyJ...`)
4. Update `.env.local`:

```bash
SUPABASE_SERVICE_KEY=eyJhbG...your_actual_service_role_key_here
```

### 5. Setup Stripe Webhook

**For Development (Local Testing)**:

Install Stripe CLI:
```bash
# Mac
brew install stripe/stripe-cli/stripe

# Windows
scoop install stripe

# Linux
wget -O stripe.tar.gz https://github.com/stripe/stripe-cli/releases/latest/download/stripe_linux_x86_64.tar.gz
tar -xvf stripe.tar.gz
```

Login and forward webhooks:
```bash
stripe login
stripe listen --forward-to http://localhost:3000/api/stripe/webhook
```

Copy the webhook signing secret (starts with `whsec_`) to `.env.local`.

**For Production (Deployed)**:

1. Go to Stripe Dashboard → Developers → Webhooks
2. Click "Add endpoint"
3. Endpoint URL: `https://dev.dinkhousepb.com/api/stripe/webhook`
4. Select events to listen for:
   - `checkout.session.completed`
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `charge.refunded`
5. Copy the webhook signing secret to production `.env`

## Testing the System

### 1. Start Development Server

```bash
cd dink-house-landing
npm run dev
```

Navigate to http://localhost:3000/campaign

### 2. Test a Contribution

1. Select a contribution tier
2. Fill out the form
3. Use Stripe test card: `4242 4242 4242 4242`
   - Expiry: Any future date
   - CVC: Any 3 digits
   - ZIP: Any 5 digits

### 3. Verify Database Updates

Check Supabase tables after successful payment:

```sql
-- Check contributions
SELECT * FROM crowdfunding.contributions ORDER BY created_at DESC LIMIT 5;

-- Check founders wall
SELECT * FROM crowdfunding.founders_wall ORDER BY created_at DESC;

-- Check campaign totals
SELECT name, current_amount, goal_amount, backer_count
FROM crowdfunding.campaign_types;
```

## Stripe Test Cards

Use these test cards for different scenarios:

| Card Number | Scenario |
|-------------|----------|
| 4242 4242 4242 4242 | Success |
| 4000 0025 0000 3155 | Requires authentication |
| 4000 0000 0000 9995 | Declined (insufficient funds) |
| 4000 0000 0000 0002 | Declined (generic) |

## Production Deployment Checklist

### Before Going Live:

- [ ] Run database migration on production Supabase
- [ ] Run seed data on production database
- [ ] Switch to Stripe Live Mode keys
- [ ] Setup production webhook endpoint
- [ ] Update `.env.production` with live keys
- [ ] Test with real cards in small amounts
- [ ] Enable Stripe fraud prevention
- [ ] Setup email notifications (optional)
- [ ] Add analytics tracking
- [ ] Test mobile responsiveness
- [ ] Review Stripe dashboard settings

### Security Checklist:

- [ ] Verify webhook signature validation is working
- [ ] Ensure service role key is not exposed to client
- [ ] Check RLS policies are enabled
- [ ] Test unauthorized access attempts
- [ ] Verify HTTPS is enforced
- [ ] Review Stripe checkout session expiration

## Troubleshooting

### Webhook Not Receiving Events

1. Check webhook endpoint is publicly accessible
2. Verify webhook secret matches Stripe Dashboard
3. Check Stripe Dashboard → Webhooks → Logs for errors
4. Ensure Next.js API route has `bodyParser: false`

### Payment Succeeds But Database Not Updating

1. Check Supabase service role key is correct
2. Verify tables exist in `crowdfunding` schema
3. Check API logs for errors
4. Ensure triggers are enabled
5. Review RLS policies

### Contribution Tier Shows as Full

1. Check `max_backers` vs `current_backers` in DB
2. Verify webhook successfully updated counts
3. Manually fix if needed:
```sql
UPDATE crowdfunding.contribution_tiers
SET current_backers = (
  SELECT COUNT(*) FROM crowdfunding.contributions
  WHERE tier_id = contribution_tiers.id AND status = 'completed'
)
WHERE id = 'tier-id-here';
```

### Founders Wall Not Displaying

1. Check `is_public = true` on contributions
2. Verify trigger `trigger_upsert_founders_wall` exists
3. Check `status = 'completed'` on contributions
4. Review founders_wall table for entries

## Next Steps & Enhancements

### Recommended Additions:

1. **Email Notifications**
   - Thank you emails via SendGrid (already configured)
   - Contribution receipts
   - Milestone announcements

2. **Admin Dashboard**
   - View all contributions
   - Manage campaigns
   - Export backer data
   - Refund processing

3. **Enhanced Features**
   - Recurring contributions
   - Gift contributions
   - Team/group contributions
   - Social sharing buttons
   - Progress milestone celebrations

4. **Analytics**
   - Google Analytics event tracking
   - Conversion funnel analysis
   - Popular tier analysis
   - Geographic distribution

## File Structure

```
dink-house/
├── dink-house-landing/
│   ├── pages/
│   │   ├── campaign.tsx              # Main campaign page
│   │   └── api/
│   │       └── stripe/
│   │           ├── create-checkout.ts # Checkout session creation
│   │           └── webhook.ts         # Stripe webhook handler
│   ├── components/
│   │   └── ContributionModal.tsx     # Contribution form modal
│   └── .env.local                    # Environment variables
│
└── dink-house-db/
    ├── sql/
    │   ├── modules/
    │   │   └── 26-crowdfunding-schema.sql  # Database schema
    │   └── seeds/
    │       └── crowdfunding-seed.sql       # Sample data
    └── api/functions/
        └── stripe-payments/
            └── index.ts                    # Supabase Edge Function (optional)
```

## Support

### Resources:
- [Stripe Documentation](https://stripe.com/docs)
- [Supabase Documentation](https://supabase.com/docs)
- [Next.js API Routes](https://nextjs.org/docs/api-routes/introduction)

### Need Help?
1. Check Stripe Dashboard logs
2. Review Supabase logs
3. Check browser console for frontend errors
4. Review server logs for API errors

## Campaign URLs

- **Development**: http://localhost:3000/campaign
- **Staging**: https://dev.dinkhousepb.com/campaign
- **Production**: https://dinkhousepb.com/campaign
