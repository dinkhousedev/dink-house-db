# Supabase API Setup Complete! 🎉

Your Dink House database now has a complete Supabase API layer configured and ready to use.

## What's Been Set Up

### ✅ Complete API Infrastructure

1. **Database Layer**
   - REST API views in `api` schema
   - Row Level Security (RLS) policies on all tables
   - Database functions for complex operations
   - Realtime subscriptions configuration

2. **Supabase Services**
   - PostgREST for REST API
   - GoTrue for authentication
   - Realtime for websocket subscriptions
   - Storage API for file uploads
   - Edge Functions for serverless logic
   - Kong API Gateway for routing

3. **Security**
   - Row Level Security on all tables
   - JWT authentication
   - API key management
   - Rate limiting
   - CORS configuration

4. **Development Tools**
   - Complete API documentation
   - Testing suite with Jest
   - Migration scripts
   - Docker Compose configurations

## Quick Start

### Option 1: Use Current Setup (Basic)
Your existing setup already works with basic Supabase features:

```bash
# Start the current setup
docker-compose up -d

# Access services
- Database: localhost:9432
- Studio: localhost:9000
- API Gateway: localhost:9002
```

### Option 2: Full Supabase Stack (Recommended)
For complete Supabase functionality including auth, realtime, and storage:

```bash
# Start the full Supabase stack
docker-compose -f docker-compose-supabase.yml up -d

# Access all services
- PostgREST API: localhost:9003
- Auth Service: localhost:9999
- Realtime: localhost:9004
- Storage: localhost:9005
- Edge Functions: localhost:9006
- Studio: localhost:9000
- Kong Gateway: localhost:9002
```

## Using the API

### Install Supabase Client

```bash
npm install @supabase/supabase-js
```

### Basic Usage

```javascript
import { createClient } from '@supabase/supabase-js';

// Initialize client
const supabase = createClient(
  'http://localhost:9002',
  'your-anon-key-from-env'
);

// Register user
const { data: user, error } = await supabase.rpc('register_user', {
  email: 'user@example.com',
  username: 'johndoe',
  password: 'SecurePassword123!',
  first_name: 'John',
  last_name: 'Doe'
});

// Login
const { data: session } = await supabase.rpc('login', {
  email: 'user@example.com',
  password: 'SecurePassword123!'
});

// Fetch content
const { data: posts } = await supabase
  .from('content_published')
  .select('*')
  .order('published_at', { ascending: false });

// Submit contact form
const { data: inquiry } = await supabase.rpc('submit_contact_form', {
  form_id: 'uuid',
  name: 'John Doe',
  email: 'john@example.com',
  message: 'Hello!'
});

// Subscribe to realtime updates
const channel = supabase
  .channel('content-updates')
  .on('postgres_changes', {
    event: '*',
    schema: 'content',
    table: 'pages'
  }, (payload) => {
    console.log('Content updated:', payload);
  })
  .subscribe();
```

## Database Schema

Your database includes these schemas:

- **auth**: User authentication and sessions
- **content**: Pages, categories, and media
- **contact**: Forms and inquiries
- **launch**: Campaigns and subscribers
- **system**: Settings and logs
- **api**: REST API views

## Available API Endpoints

### Authentication
- `POST /rpc/register_user` - Register new user
- `POST /rpc/login` - User login
- `POST /rpc/logout` - User logout
- `POST /rpc/refresh_token` - Refresh access token

### Content
- `GET /content_published` - Get published content
- `POST /rpc/upsert_content` - Create/update content
- `GET /categories_with_counts` - Get categories

### Contact
- `GET /contact_forms_public` - Get public forms
- `POST /rpc/submit_contact_form` - Submit form

### Campaigns
- `GET /launch_campaigns_active` - Get active campaigns
- `POST /rpc/subscribe_to_campaign` - Subscribe
- `POST /rpc/unsubscribe` - Unsubscribe

## Testing

Run the test suite:

```bash
# Install dependencies
npm install

# Run tests
npm test

# Run specific test
npm test auth.test.js
```

## Migration to Supabase Cloud

When ready to deploy to production:

```bash
# Use the migration script
./migrate-to-supabase.sh

# Follow the interactive menu:
1. Create local backup
2. Export schema and data
3. Connect to your Supabase project
4. Import the database
5. Verify migration
```

## Environment Variables

Update your `.env` file with Supabase credentials:

```env
# Local Development
SUPABASE_URL=http://localhost:9002
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key

# Production (Supabase Cloud)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-production-anon-key
SUPABASE_SERVICE_KEY=your-production-service-key
```

## Security Checklist

Before going to production:

- [ ] Change all default passwords
- [ ] Generate new JWT secrets
- [ ] Update API keys
- [ ] Configure proper CORS origins
- [ ] Enable SSL/TLS
- [ ] Review RLS policies
- [ ] Set up email provider
- [ ] Configure storage buckets
- [ ] Enable monitoring

## File Structure

```
dink-house-db/
├── api/
│   ├── config/          # API configuration
│   ├── lib/             # Supabase client library
│   ├── functions/       # Edge functions
│   ├── docs/            # API documentation
│   └── tests/           # Test suite
├── sql/
│   └── modules/
│       ├── 10-api-views.sql      # REST API views
│       ├── 11-rls-policies.sql   # Row Level Security
│       ├── 12-api-functions.sql  # Database functions
│       └── 13-realtime-config.sql # Realtime setup
├── docker-compose.yml              # Basic setup
├── docker-compose-supabase.yml    # Full Supabase stack
├── kong-supabase.yml              # API gateway config
├── migrate-to-supabase.sh        # Migration script
└── package.json                   # Node dependencies
```

## Next Steps

1. **Test the API**: Use the test suite to verify everything works
2. **Review Security**: Check RLS policies match your requirements
3. **Configure Email**: Set up SMTP for email notifications
4. **Add Storage**: Configure buckets for file uploads
5. **Deploy**: Migrate to Supabase Cloud when ready

## Troubleshooting

### Database Connection Issues
```bash
# Check if services are running
docker-compose ps

# View logs
docker-compose logs -f postgres
docker-compose logs -f rest
```

### API Not Responding
```bash
# Test PostgREST directly
curl http://localhost:9003/

# Test through Kong
curl http://localhost:9002/rest/v1/
```

### Realtime Not Working
```bash
# Check realtime service
docker-compose logs -f realtime

# Verify publication exists
docker exec dink-house-db psql -U postgres -d dink_house -c "\dRp"
```

## Documentation

- [Full API Documentation](api/docs/API.md)
- [Supabase Docs](https://supabase.com/docs)
- [Database Schema](README.md#database-schema)

## Support

For issues or questions:
1. Check the [API documentation](api/docs/API.md)
2. Review the [main README](README.md)
3. Check Supabase Studio at http://localhost:9000

---

Your Supabase API is ready! Start building amazing applications with real-time features, authentication, and file storage. 🚀