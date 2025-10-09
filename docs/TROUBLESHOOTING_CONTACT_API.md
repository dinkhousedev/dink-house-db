# Troubleshooting Contact API Error

## Error
```
Error processing contact submission: Error: Failed to process signup
POST /api/contact 500 in 448ms
```

## Root Cause

The error is happening because the **database migrations have not been applied yet**.

The updated `submit_newsletter_signup()` function that returns `requires_confirmation: true` is in the migration files, but these need to be manually applied to your Supabase database.

## Solution

### Step 1: Apply Database Migrations

Go to Supabase SQL Editor:
https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql/new

Apply these 3 migration files **in order**:

#### Migration 1: Add Schema Changes
Copy and paste contents of:
`dink-house-db/supabase/migrations/20251002150000_add_newsletter_opt_in_out.sql`

Click **Run** and verify success.

#### Migration 2: Update Functions
Copy and paste contents of:
`dink-house-db/supabase/migrations/20251002150100_newsletter_opt_in_functions.sql`

Click **Run** and verify success.

#### Migration 3: Add Email Template
Copy and paste contents of:
`dink-house-db/supabase/migrations/20251002150200_confirmation_email_template.sql`

Click **Run** and verify success.

### Step 2: Verify Migrations Applied

Run this SQL query to check:
```sql
-- Check if unsubscribe_token column exists
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'launch'
  AND table_name = 'launch_subscribers'
  AND column_name = 'unsubscribe_token';

-- Check if status column exists
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'launch'
  AND table_name = 'launch_subscribers'
  AND column_name = 'status';

-- Check if new function exists
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'confirm_newsletter_subscription';
```

Expected results:
- First query returns: `unsubscribe_token`
- Second query returns: `status`
- Third query returns: `confirm_newsletter_subscription`

### Step 3: Test the Form Again

After migrations are applied:
1. Open your landing page
2. Fill out the waitlist/newsletter form
3. Check the consent checkbox
4. Click submit

**Expected behavior:**
- No errors in console
- Success message: "Check your email to confirm your subscription"
- Modal closes after 3 seconds

## Debugging Steps

### Check Console Logs

The API now logs the response. Look for:
```
API Response: {
  "success": true,
  "requires_confirmation": true,
  "message": "Please check your email...",
  "subscriber_id": "...",
  "verification_token": "..."
}
```

### If Still Getting Errors

1. **Check API URL:**
   ```javascript
   // In pages/api/contact.ts
   const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://api.dinkhousepb.com";
   ```

   Verify this matches your Supabase project URL:
   - Should be: `https://wchxzbuuwssrnaxshseu.supabase.co`
   - Not: `https://api.dinkhousepb.com`

2. **Check API Key:**
   ```bash
   echo $NEXT_PUBLIC_SUPABASE_ANON_KEY
   ```

   Should be your Supabase anon key, not empty.

3. **Check Function Exists:**
   ```sql
   SELECT * FROM pg_proc
   WHERE proname = 'submit_newsletter_signup';
   ```

4. **Test Function Directly:**
   ```sql
   SELECT public.submit_newsletter_signup(
     'test@example.com',
     'Test',
     'User'
   );
   ```

   Should return JSON with `requires_confirmation: true`

### Common Issues

#### Issue: "Function does not exist"
**Solution:** Migrations not applied. Go to Step 1.

#### Issue: "Column does not exist"
**Solution:** First migration not applied. Apply migration 1.

#### Issue: "Success: false"
**Solution:** Check the error message in the response. Might be:
- Invalid email format
- Database connection issue
- Permission issue

#### Issue: "Already subscribed"
**Solution:** This is actually success! The email is already in the database. Try with a different email.

## Quick Fix (Temporary)

If you can't apply migrations immediately, you can temporarily modify the API to handle both old and new responses:

```typescript
// In pages/api/contact.ts, line ~105
if (actualResult.success) {
  // Handle already subscribed
  if (actualResult.already_subscribed) {
    return res.status(200).json({
      success: true,
      message: "You're already on our waitlist!",
      data: contactData,
    });
  }

  // Handle new confirmation flow (new function)
  if (actualResult.requires_confirmation) {
    return res.status(200).json({
      success: true,
      message: "Check your email to confirm your subscription!",
      data: contactData,
    });
  }

  // Handle old flow (legacy - if migrations not applied)
  return res.status(200).json({
    success: true,
    message: "Successfully joined the waitlist!",
    data: contactData,
  });
}
```

This way it works with both old and new database schemas.

## Verification Checklist

After applying migrations, verify:

- [ ] Migrations applied successfully (no SQL errors)
- [ ] `unsubscribe_token` column exists in `launch_subscribers`
- [ ] `status` column exists in `launch_subscribers`
- [ ] `confirm_newsletter_subscription()` function exists
- [ ] `unsubscribe_newsletter()` function exists
- [ ] Newsletter form submits successfully
- [ ] Waitlist modal submits successfully
- [ ] Console shows: `"requires_confirmation": true` in API response
- [ ] No 500 errors in browser console

## Support

If issues persist:

1. **Check server logs:**
   ```bash
   # Next.js dev server logs
   npm run dev
   ```

2. **Check Supabase logs:**
   https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/logs/explorer

3. **Test the function directly in SQL Editor:**
   ```sql
   SELECT public.submit_newsletter_signup(
     'youremail@test.com',
     'Your',
     'Name'
   );
   ```

4. **Check network tab:**
   - Open browser DevTools
   - Go to Network tab
   - Submit form
   - Click on `/api/contact` request
   - Check Response tab for actual error

## Related Files

- `pages/api/contact.ts` - API handler (updated with debugging)
- `components/WaitlistModal.tsx` - Modal component
- `components/newsletter-form.tsx` - Newsletter form
- `dink-house-db/supabase/migrations/` - Migration files to apply
- `DEPLOYMENT_SUMMARY.md` - Complete deployment guide
