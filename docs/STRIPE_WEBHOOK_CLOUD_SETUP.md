# Stripe Webhook Cloud Setup Guide

This guide walks you through setting up Stripe webhooks to work with your cloud-deployed Next.js application.

## Prerequisites

- Your landing site must be deployed to a public URL (Vercel, Netlify, AWS Amplify, etc.)
- Stripe account with test mode enabled
- Access to Stripe Dashboard

## Step 1: Deploy Your Landing Site

Make sure your `dink-house-landing` is deployed to production with these environment variables:

```bash
STRIPE_SECRET_KEY=your-stripe-secret-key-here  # Get from Stripe Dashboard
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=your-stripe-publishable-key-here  # Get from Stripe Dashboard
STRIPE_WEBHOOK_SECRET=whsec_XXXXXX  # You'll get this in Step 3
SUPABASE_SERVICE_KEY=your_service_role_key_here
NEXT_PUBLIC_SUPABASE_URL=https://wchxzbuuwssrnaxshseu.supabase.co
NEXT_PUBLIC_SITE_URL=https://your-production-domain.com
```

## Step 2: Locate Your Webhook Endpoint

Your webhook endpoint will be at:
```
https://your-production-domain.com/api/stripe/webhook
```

For example:
- Vercel: `https://dinkhousepb.com/api/stripe/webhook`
- Netlify: `https://dinkhousepb.netlify.app/api/stripe/webhook`
- Custom domain: `https://dinkhousepb.com/api/stripe/webhook`

## Step 3: Configure Stripe Webhook

### 3.1 Access Stripe Dashboard

1. Go to https://dashboard.stripe.com
2. Make sure you're in **Test Mode** (toggle in top right)
3. Navigate to **Developers** → **Webhooks**

### 3.2 Add Endpoint

1. Click **"Add endpoint"** button
2. Enter your webhook URL: `https://your-domain.com/api/stripe/webhook`
3. Click **"Select events"**
4. Select these events:
   - ✅ `checkout.session.completed`
   - ✅ `payment_intent.succeeded`
   - ✅ `payment_intent.payment_failed`
   - ✅ `charge.refunded`
5. Click **"Add events"**
6. Click **"Add endpoint"**

### 3.3 Get Webhook Secret

1. After creating the endpoint, you'll see it in the list
2. Click on the endpoint URL to view details
3. In the **"Signing secret"** section, click **"Reveal"**
4. Copy the signing secret (starts with `whsec_`)
5. Add this to your environment variables as `STRIPE_WEBHOOK_SECRET`

## Step 4: Update Environment Variables

### For Vercel:
1. Go to your project settings
2. Navigate to **Environment Variables**
3. Add/update: `STRIPE_WEBHOOK_SECRET=whsec_...`
4. Redeploy your application

### For Netlify:
1. Go to **Site settings** → **Environment variables**
2. Add/update: `STRIPE_WEBHOOK_SECRET=whsec_...`
3. Trigger a new deploy

### For AWS Amplify:
1. Go to **App settings** → **Environment variables**
2. Add/update: `STRIPE_WEBHOOK_SECRET=whsec_...`
3. Redeploy the app

## Step 5: Test the Webhook

### Using Stripe CLI (Development Testing)

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login to Stripe
stripe login

# Forward events to your cloud endpoint
stripe listen --forward-to https://your-domain.com/api/stripe/webhook
```

### Using Stripe Dashboard (Production Testing)

1. Go to **Developers** → **Webhooks**
2. Click on your webhook endpoint
3. Click **"Send test webhook"**
4. Select `checkout.session.completed`
5. Click **"Send test webhook"**
6. Check the **Response** tab to see if it succeeded (should return `200 OK`)

### Full End-to-End Test

1. Go to your campaign page: `https://your-domain.com/campaign`
2. Select a contribution tier
3. Fill out the form with test data:
   - Email: test@example.com
   - Name: Test User
4. Click "Continue to Payment"
5. Use Stripe test card: `4242 4242 4242 4242`
   - Expiry: Any future date
   - CVC: Any 3 digits
   - ZIP: Any 5 digits
6. Complete the payment
7. Check Supabase to verify:
   - Contribution status is "completed"
   - Backer totals updated
   - Founders wall entry created

## Step 6: Verify Database Updates

After a successful test payment, check your Supabase database:

```sql
-- Check contributions
SELECT * FROM crowdfunding.contributions
WHERE status = 'completed'
ORDER BY completed_at DESC
LIMIT 5;

-- Check founders wall
SELECT * FROM crowdfunding.founders_wall
ORDER BY total_contributed DESC;

-- Check backer totals
SELECT * FROM crowdfunding.backers
ORDER BY total_contributed DESC;

-- Check campaign totals
SELECT name, current_amount, goal_amount, backer_count
FROM crowdfunding.campaign_types;
```

## Troubleshooting

### Webhook Returns 400 Error
- Check that `STRIPE_WEBHOOK_SECRET` is set correctly
- Verify the secret matches the one in Stripe Dashboard
- Redeploy after updating environment variables

### Webhook Returns 500 Error
- Check Vercel/Netlify logs for error details
- Verify `SUPABASE_SERVICE_KEY` is set and valid
- Check that the crowdfunding schema is deployed to Supabase

### Database Not Updating
- Check Supabase logs: https://wchxzbuuwssrnaxshseu.supabase.co → Logs
- Verify Row Level Security policies allow service role access
- Check that triggers are enabled on the contributions table

### Webhook Not Receiving Events
- Verify webhook URL is correct and publicly accessible
- Check that selected events match the code expectations
- Test with Stripe CLI to rule out network issues

## Going Live (Production Mode)

When ready to accept real payments:

1. **Complete Stripe account activation**
   - Provide business details
   - Connect bank account
   - Verify identity

2. **Switch to Live Mode keys**
   - In Stripe Dashboard, toggle to **Live Mode**
   - Go to **Developers** → **API Keys**
   - Copy live keys (start with `pk_live_` and `sk_live_`)

3. **Create Live Webhook**
   - In **Live Mode**, go to **Developers** → **Webhooks**
   - Add endpoint with same URL
   - Select same events
   - Get new webhook secret (starts with `whsec_`)

4. **Update Production Environment Variables**
   ```bash
   STRIPE_SECRET_KEY=sk_live_XXXXXXXXX
   NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_live_XXXXXXXXX
   STRIPE_WEBHOOK_SECRET=whsec_XXXXXXXXX  # Live mode secret
   ```

5. **Redeploy** your application with live keys

## Security Best Practices

1. ✅ Never commit API keys to git
2. ✅ Use environment variables for all secrets
3. ✅ Keep test and live keys separate
4. ✅ Verify webhook signatures (already implemented in code)
5. ✅ Use HTTPS only (enforced by Stripe)
6. ✅ Monitor webhook logs regularly
7. ✅ Set up Stripe email notifications for failed payments

## Monitoring

- **Stripe Dashboard**: Monitor payments in real-time
- **Webhook Logs**: View all webhook events and responses
- **Supabase Logs**: Monitor database operations
- **Application Logs**: Check Vercel/Netlify function logs

## Support

For issues:
1. Check Stripe Dashboard webhook logs
2. Review application deployment logs
3. Check Supabase database logs
4. Verify environment variables are set correctly
