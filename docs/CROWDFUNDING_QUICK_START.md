# Crowdfunding Quick Start Guide

Get the crowdfunding campaign running in 10 minutes.

## Prerequisites

- Supabase project: https://wchxzbuuwssrnaxshseu.supabase.co
- Stripe account (test mode)
- Node.js and npm installed

## Step 1: Database Setup (2 minutes)

### Option A: Via Supabase Studio (Recommended)

1. Go to https://wchxzbuuwssrnaxshseu.supabase.co
2. Navigate to **SQL Editor**
3. Click **New Query**
4. Copy and paste content from: `dink-house-db/sql/modules/26-crowdfunding-schema.sql`
5. Click **Run** (or press Cmd/Ctrl + Enter)
6. Wait for "Success" message
7. Create new query and paste content from: `dink-house-db/sql/seeds/crowdfunding-seed.sql`
8. Click **Run**

### Option B: Via Command Line

```bash
cd dink-house-db
psql "postgresql://postgres:[password]@db.[project-ref].supabase.co:5432/postgres" \
  -f sql/modules/26-crowdfunding-schema.sql \
  -f sql/seeds/crowdfunding-seed.sql
```

**Verify**: Check that tables exist in Database → Tables → Select schema: crowdfunding

## Step 2: Get Stripe Keys (3 minutes)

1. Go to https://dashboard.stripe.com
2. Make sure **"Test mode"** toggle is ON (top right)
3. Navigate to **Developers** → **API keys**
4. Copy your keys:
   - **Publishable key**: `pk_test_...` (already have: pk_test_51SBgorQ4M7SOiop2MZVKL5Duoad0OwEi4weFYR8W5Vg6YzqcTcX4Ztmk7Y0rjI06xZKFGNwkFbwJJopgJq88uEdT00KtlYiPkP)
   - **Secret key**: `sk_test_...` (click "Reveal test key" to copy)

## Step 3: Get Supabase Service Key (1 minute)

1. Go to https://wchxzbuuwssrnaxshseu.supabase.co
2. Navigate to **Settings** → **API**
3. Scroll to **Project API keys**
4. Copy the `service_role` key (starts with `eyJ...`)

## Step 4: Update Environment Variables (2 minutes)

Edit `dink-house-landing/.env.local`:

```bash
# Update this line with your actual Stripe secret key
STRIPE_SECRET_KEY=sk_test_YOUR_ACTUAL_SECRET_KEY_HERE

# This is already set correctly
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_51SBgorQ4M7SOiop2MZVKL5Duoad0OwEi4weFYR8W5Vg6YzqcTcX4Ztmk7Y0rjI06xZKFGNwkFbwJJopgJq88uEdT00KtlYiPkP

# Update this with your actual Supabase service key
SUPABASE_SERVICE_KEY=eyJhbG...YOUR_ACTUAL_SERVICE_KEY_HERE

# Webhook secret - we'll get this in Step 5
STRIPE_WEBHOOK_SECRET=whsec_...
```

## Step 5: Setup Stripe Webhook (2 minutes)

### For Local Development:

Install Stripe CLI (one time only):

**Mac:**
```bash
brew install stripe/stripe-cli/stripe
```

**Windows:**
```bash
scoop install stripe
```

**Linux:**
```bash
wget https://github.com/stripe/stripe-cli/releases/latest/download/stripe_linux_x86_64.tar.gz
tar -xvf stripe_linux_x86_64.tar.gz
sudo mv stripe /usr/local/bin/
```

Then run:
```bash
# Login to Stripe
stripe login

# Start webhook forwarding (keep this running)
stripe listen --forward-to http://localhost:3000/api/stripe/webhook
```

Copy the webhook signing secret (starts with `whsec_`) and add to `.env.local`:
```bash
STRIPE_WEBHOOK_SECRET=whsec_YOUR_WEBHOOK_SECRET_HERE
```

## Step 6: Start Development Server

```bash
cd dink-house-landing
npm run dev
```

Open http://localhost:3000/campaign

## Step 7: Test a Contribution

1. Click on any contribution tier
2. Fill out the form:
   - First Name: Test
   - Last Initial: U
   - Email: test@example.com
   - City: Belton
   - State: TX
3. Click "Continue to Payment"
4. Use Stripe test card: `4242 4242 4242 4242`
   - Expiry: Any future date (e.g., 12/25)
   - CVC: Any 3 digits (e.g., 123)
   - ZIP: Any 5 digits (e.g., 76513)
5. Click "Pay"
6. You should be redirected back to campaign page
7. Check the Founders Wall section - your name should appear!

## Verify Everything Works

### Check Database:

Go to Supabase Studio → Table Editor → crowdfunding schema

**Check contributions:**
```sql
SELECT * FROM crowdfunding.contributions ORDER BY created_at DESC;
```
Status should be "completed"

**Check founders wall:**
```sql
SELECT * FROM crowdfunding.founders_wall;
```
Should show "Test U., Belton, TX"

**Check campaign totals:**
```sql
SELECT name, current_amount, backer_count FROM crowdfunding.campaign_types;
```
Current amount should be updated

### Check Stripe:

1. Go to Stripe Dashboard → Payments
2. You should see your test payment
3. Go to Developers → Webhooks → Your endpoint
4. Click to see event logs - should show successful events

## Common Issues & Fixes

### Issue: "Failed to create checkout session"

**Fix**: Check that `STRIPE_SECRET_KEY` in `.env.local` is correct and starts with `sk_test_`

### Issue: "Missing contribution_id in session metadata"

**Fix**: Webhook secret is wrong. Re-run `stripe listen` and copy the new secret to `.env.local`

### Issue: "Table doesn't exist"

**Fix**: Re-run the database schema SQL in Supabase Studio

### Issue: Payment succeeds but database not updating

**Fix 1**: Check that `SUPABASE_SERVICE_KEY` is the service_role key, not the anon key

**Fix 2**: Restart the stripe webhook listener:
```bash
stripe listen --forward-to http://localhost:3000/api/stripe/webhook
```

**Fix 3**: Check Supabase logs (Dashboard → Logs → API)

### Issue: "Founders Wall not showing"

**Fix**: Check that contribution has `is_public = true` and `status = 'completed'`:
```sql
UPDATE crowdfunding.contributions
SET is_public = true
WHERE id = 'contribution-id';
```

## Next Steps

### For Production:

1. **Get Live Stripe Keys**:
   - Switch "Test mode" OFF in Stripe Dashboard
   - Copy live keys (start with `pk_live_` and `sk_live_`)
   - Update production environment variables

2. **Setup Production Webhook**:
   - Stripe Dashboard → Developers → Webhooks
   - Add endpoint: `https://dinkhousepb.com/api/stripe/webhook`
   - Select events: checkout.session.completed, payment_intent.succeeded, payment_intent.payment_failed, charge.refunded
   - Copy webhook signing secret to production `.env`

3. **Deploy Database**:
   - Run migration on production Supabase
   - Run seed data
   - Verify RLS policies

4. **Deploy Frontend**:
   - Update `.env.production` with live keys
   - Deploy to production
   - Test with real card (small amount)

### Optional Enhancements:

- Add email notifications using SendGrid (already configured)
- Add campaign milestone alerts
- Create admin dashboard for managing contributions
- Add social sharing buttons
- Implement campaign updates/news section

## Support Resources

- **Stripe Docs**: https://stripe.com/docs
- **Supabase Docs**: https://supabase.com/docs
- **Stripe Test Cards**: https://stripe.com/docs/testing

## Test Card Reference

| Scenario | Card Number |
|----------|-------------|
| Success | 4242 4242 4242 4242 |
| Requires 3D Secure | 4000 0025 0000 3155 |
| Declined | 4000 0000 0000 9995 |
| Fraud blocked | 4100 0000 0000 0019 |

Use any future expiry, any 3-digit CVC, any ZIP code.

---

**You're all set!** 🎉

The crowdfunding campaign should now be fully functional. Test thoroughly before going live with real payments.
