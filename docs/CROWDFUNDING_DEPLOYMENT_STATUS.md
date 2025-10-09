# Crowdfunding System Deployment Status

## ✅ What's Complete

### Database (Supabase Cloud)
- ✅ Schema deployed to `https://wchxzbuuwssrnaxshseu.supabase.co`
- ✅ 7 tables created in `crowdfunding` schema
- ✅ Triggers and functions active
- ✅ 3 campaigns seeded with tiers
- ✅ Row Level Security enabled

### Frontend (dinkhousepb.com)
- ✅ Campaign page at `/campaign`
- ✅ ContributionModal component
- ✅ Founders wall display
- ✅ Stripe checkout integration

### API Routes
- ✅ `/api/stripe/create-checkout.ts` - Creates checkout sessions
- ✅ `/api/stripe/webhook.ts` - Processes webhook events
- ✅ Webhook URL: `https://dinkhousepb.com/api/stripe/webhook`

### Dependencies
- ✅ Stripe package installed in both projects
- ✅ Supabase client configured

## 🔧 Configuration Needed

### 1. Stripe Webhook Setup (Required for payments to work)

**Do this in Stripe Dashboard:**
1. Go to https://dashboard.stripe.com
2. Enable **Test Mode** (toggle in top right)
3. Navigate to: **Developers** → **Webhooks**
4. Click **"Add endpoint"**
5. Enter webhook URL:
   ```
   https://dinkhousepb.com/api/stripe/webhook
   ```
6. Select these events:
   - `checkout.session.completed`
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `charge.refunded`
7. Click **"Add endpoint"**
8. Click on the new endpoint
9. Click **"Reveal"** under "Signing secret"
10. Copy the secret (starts with `whsec_`)

### 2. Update Environment Variables

**On your deployment platform (Vercel/Netlify/Amplify):**

Add or update these environment variables:
```bash
# Stripe Keys (Test Mode)
STRIPE_SECRET_KEY=your-stripe-secret-key-here  # ⚠️ Get this from Stripe Dashboard
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=your-stripe-publishable-key-here  # ⚠️ Get this from Stripe Dashboard
STRIPE_WEBHOOK_SECRET=whsec_PASTE_YOUR_SECRET_HERE  # ⚠️ Get this from Stripe Dashboard

# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://wchxzbuuwssrnaxshseu.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjaHh6YnV1d3Nzcm5heHNoc2V1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg5OTA4NzcsImV4cCI6MjA3NDU2Njg3N30.u23ktCLo4GgmOfxZkk4UnCepgftnZzZLChPgFfWeqKY
SUPABASE_SERVICE_KEY=YOUR_SERVICE_ROLE_KEY_HERE  # ⚠️ Get from Supabase Dashboard

# Site Config
NEXT_PUBLIC_SITE_URL=https://dinkhousepb.com
```

**⚠️ Important:** After updating environment variables, **redeploy** your site!

### 3. Get Supabase Service Role Key

1. Go to https://wchxzbuuwssrnaxshseu.supabase.co
2. Click **Settings** → **API**
3. Under "Project API keys", find **"service_role"**
4. Click **"Reveal"** and copy the key
5. Add to environment variables as `SUPABASE_SERVICE_KEY`

## 🧪 Testing

### Test Payment Flow

1. Visit: https://dinkhousepb.com/campaign
2. Select any contribution tier
3. Fill out the form:
   - Email: test@example.com
   - Name: Test
   - Last Initial: U
4. Click "Continue to Payment"
5. Use Stripe test card:
   - Card: `4242 4242 4242 4242`
   - Expiry: Any future date
   - CVC: Any 3 digits
   - ZIP: Any 5 digits
6. Complete payment
7. Verify in Supabase:
   ```sql
   SELECT * FROM crowdfunding.contributions WHERE status = 'completed';
   SELECT * FROM crowdfunding.founders_wall;
   ```

### Verify Webhook

In Stripe Dashboard:
1. Go to **Developers** → **Webhooks**
2. Click on your webhook endpoint
3. Click **"Send test webhook"**
4. Select `checkout.session.completed`
5. Verify response is **200 OK**

## 📊 Current Campaigns

### 1. Build the Courts Campaign
- Goal: $75,000
- Tiers: $25, $50, $100, $250, $500, $1,000, $5,000

### 2. Dink Practice Boards
- Goal: $1,200
- Multiple tiers

### 3. Ball Machine Equipment
- Goal: $7,000
- Multiple tiers

## 🚀 Going Live (Production)

When ready to accept real payments:

### 1. Activate Stripe Account
- Provide business details
- Connect bank account
- Verify identity

### 2. Create Live Webhook
- Switch to **Live Mode** in Stripe
- Create new webhook endpoint (same URL)
- Get live webhook secret

### 3. Update to Live Keys
```bash
STRIPE_SECRET_KEY=sk_live_XXXXX
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_live_XXXXX
STRIPE_WEBHOOK_SECRET=whsec_XXXXX  # From live webhook
```

### 4. Redeploy

## 📁 Key Files

- Schema: `dink-house-db/sql/modules/26-crowdfunding-schema.sql`
- Seed Data: `dink-house-db/sql/seeds/crowdfunding-seed.sql`
- Campaign Page: `dink-house-landing/pages/campaign.tsx`
- Modal: `dink-house-landing/components/ContributionModal.tsx`
- Checkout API: `dink-house-landing/pages/api/stripe/create-checkout.ts`
- Webhook API: `dink-house-landing/pages/api/stripe/webhook.ts`
- Setup Guide: `STRIPE_WEBHOOK_CLOUD_SETUP.md`

## 🆘 Troubleshooting

### Webhook returns 400
- Check `STRIPE_WEBHOOK_SECRET` is set correctly
- Verify webhook secret matches Stripe Dashboard
- Redeploy after updating env vars

### Webhook returns 500
- Check deployment logs (Vercel/Netlify)
- Verify `SUPABASE_SERVICE_KEY` is set
- Check Supabase logs

### Database not updating
- Verify RLS policies allow service role
- Check Supabase function logs
- Ensure triggers are enabled

### Payment succeeds but no database update
- Check webhook is being called (Stripe Dashboard → Webhooks → Logs)
- Verify webhook secret is correct
- Check application logs for errors

## 📞 Support Resources

- Stripe Dashboard: https://dashboard.stripe.com
- Supabase Dashboard: https://wchxzbuuwssrnaxshseu.supabase.co
- Documentation: `STRIPE_WEBHOOK_CLOUD_SETUP.md`
