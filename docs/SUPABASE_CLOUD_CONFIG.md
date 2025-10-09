# Supabase Cloud Configuration Guide

## Your Supabase Cloud Instance Details

- **Project URL**: https://wchxzbuuwssrnaxshseu.supabase.co
- **Project ID**: wchxzbuuwssrnaxshseu
- **Region**: us-east-2
- **Storage Bucket**: dink-files (created)
- **Logo URL**: https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dink-house-logo.png

## Complete Cloud Setup

### 1. Run Migration in Supabase SQL Editor

1. Go to: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/sql/new
2. Copy and paste the entire contents of `migrate-to-cloud.sql`
3. Click "Run" to create all tables and functions

### 2. Get Your Database Connection String

1. Go to: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/settings/database
2. Copy the "Connection string" (URI format)
3. It will look like:
   ```
   postgresql://postgres.[project-id]:[password]@aws-0-us-east-2.pooler.supabase.com:6543/postgres
   ```

### 3. Update ALL Environment Files

Replace local database URLs with your Supabase Cloud connection in all `.env.local` files:

#### dink-house-db/.env.local
```env
# Use Supabase Cloud - NO LOCAL DATABASE
DATABASE_URL=[Your Supabase Connection String from Step 2]
SUPABASE_URL=https://wchxzbuuwssrnaxshseu.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndjaHh6YnV1d3Nzcm5heHNoc2V1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg5OTA4NzcsImV4cCI6MjA3NDU2Njg3N30.u23ktCLo4GgmOfxZkk4UnCepgftnZzZLChPgFfWeqKY
SUPABASE_SERVICE_KEY=[Get from Dashboard > Settings > API]
```

### 4. API Routes Already Updated

All API routes now use Supabase Cloud:
- ✅ Landing page contact form API
- ✅ Database API routes
- ✅ Admin dashboard response API

### 5. No Local Dependencies!

You NO LONGER need:
- ❌ Docker PostgreSQL container
- ❌ Local database migrations
- ❌ Local storage buckets

Everything runs in Supabase Cloud!

## Testing Cloud Integration

### Quick Test
```bash
# Test contact form submission directly to cloud
curl -X POST http://localhost:3000/api/contact-form \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Cloud",
    "lastName": "Test",
    "email": "test@example.com",
    "message": "Testing Supabase Cloud integration"
  }'
```

### Check in Supabase Dashboard
1. Go to: https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu/editor
2. Navigate to `contact` schema → `contact_inquiries` table
3. You'll see all submissions stored in the cloud

## Direct Database Access

### Using Supabase JS Client (Recommended)
```javascript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://wchxzbuuwssrnaxshseu.supabase.co',
  'your-anon-key'
)

// Insert contact inquiry
const { data, error } = await supabase
  .from('contact_inquiries')
  .insert({
    first_name: 'John',
    last_name: 'Doe',
    email: 'john@example.com',
    message: 'Hello from the cloud!'
  })

// Fetch inquiries
const { data: inquiries } = await supabase
  .from('contact_inquiries')
  .select('*')
  .order('created_at', { ascending: false })
```

### Using SQL (Direct Connection)
```javascript
const { Pool } = require('pg')

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
})

// Now all queries go directly to Supabase Cloud
const result = await pool.query(
  'SELECT * FROM contact.contact_inquiries ORDER BY created_at DESC'
)
```

## Storage Access

### Upload Files to Cloud Storage
```javascript
const { data, error } = await supabase.storage
  .from('dink-files')
  .upload('path/to/file.png', fileBuffer, {
    contentType: 'image/png',
    upsert: true
  })

// Get public URL
const { data: { publicUrl } } = supabase.storage
  .from('dink-files')
  .getPublicUrl('path/to/file.png')
```

## API Endpoints (All Cloud-Connected)

- `POST /api/contact-form` - Submits to Supabase Cloud
- `GET /api/contact/submissions` - Reads from Supabase Cloud
- `POST /api/send-response` - Uses Cloud storage for logos

## Environment Variables Summary

```env
# Supabase Cloud Configuration
NEXT_PUBLIC_SUPABASE_URL=https://wchxzbuuwssrnaxshseu.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_KEY=[Get from dashboard]
DATABASE_URL=[Get from dashboard]

# Storage
STORAGE_BUCKET=dink-files
LOGO_URL=https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dink-house-logo.png

# SendGrid
SENDGRID_API_KEY=SG.zsLBQ1JFSPG7N9eqi58dIQ...
EMAIL_FROM=contact@dinkhousepb.com
ADMIN_EMAIL=contact@dinkhousepb.com
```

## Benefits of Cloud-Only Setup

1. **No Local Database Management** - Supabase handles everything
2. **Built-in Backups** - Automatic daily backups
3. **Global CDN for Storage** - Fast asset delivery
4. **Real-time Subscriptions** - Live updates available
5. **Built-in Auth** - Can use Supabase Auth if needed
6. **SQL Editor** - Edit schemas directly in dashboard
7. **API Auto-generated** - REST and GraphQL APIs ready

## Next Development Steps

When you build new features:

1. **Create tables**: Use Supabase SQL Editor
2. **Add RLS policies**: Define in SQL Editor
3. **Upload assets**: Use Storage dashboard or API
4. **Test APIs**: Use Supabase API docs
5. **Monitor**: Check logs in dashboard

Everything is now cloud-first! 🚀