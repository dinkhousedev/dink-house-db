# Amplify Environment Variables Setup

## Required Environment Variables

Add these to your Amplify App's environment variables:

### Client-side Variables (Public)
```bash
NEXT_PUBLIC_SUPABASE_URL=http://localhost:9002
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
```

### Server-side Variables (Secret)
```bash
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU
DATABASE_URL=postgresql://postgres:DevPassword123!@localhost:9432/dink_house
```

## How to Add in Amplify Console

1. Go to AWS Amplify Console
2. Select your app
3. Navigate to **App settings** → **Environment variables**
4. Click **Manage variables**
5. Add each variable listed above
6. Click **Save**

## Using in Your Next.js/React App

```javascript
import { createClient } from '@supabase/supabase-js'

// Client-side initialization
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
)

// Server-side initialization (API routes, SSR)
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
)
```

## Security Notes

- **NEVER** expose `SUPABASE_SERVICE_ROLE_KEY` to the client
- Use `NEXT_PUBLIC_` prefix only for variables that should be accessible in the browser
- For production, replace with your actual Supabase project credentials

## Production Setup

For production, update these URLs:
```bash
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-production-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-production-service-key
```