# Dink House Supabase API Documentation

## Overview

The Dink House API is built on Supabase and PostgreSQL, providing a complete REST API, real-time subscriptions, authentication, and file storage capabilities.

## Base URL

```
Development: http://localhost:9002
Production: https://api.yourdomain.com
```

## Authentication

### API Keys

Include your API key in the request headers:

```http
apikey: your-api-key-here
Authorization: Bearer your-api-key-here
```

### JWT Tokens

For authenticated requests, use JWT tokens:

```http
Authorization: Bearer your-jwt-token-here
```

## Endpoints

### Authentication

#### Register User

```http
POST /rest/v1/rpc/register_user
Content-Type: application/json

{
  "email": "user@example.com",
  "username": "johndoe",
  "password": "SecurePassword123!",
  "first_name": "John",
  "last_name": "Doe"
}
```

**Response:**

```json
{
  "success": true,
  "user_id": "uuid",
  "verification_token": "token",
  "message": "Registration successful. Please verify your email."
}
```

#### Login

```http
POST /rest/v1/rpc/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "SecurePassword123!"
}
```

**Response:**

```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "username": "johndoe",
    "first_name": "John",
    "last_name": "Doe",
    "role": "viewer"
  },
  "session_token": "token",
  "refresh_token": "token",
  "expires_at": "2024-01-01T00:00:00Z"
}
```

#### Logout

```http
POST /rest/v1/rpc/logout
Content-Type: application/json
Authorization: Bearer your-jwt-token

{
  "session_token": "token"
}
```

#### Refresh Token

```http
POST /rest/v1/rpc/refresh_token
Content-Type: application/json

{
  "refresh_token": "token"
}
```

### Content

#### Get Published Content

```http
GET /rest/v1/content_published?select=*
```

**Query Parameters:**

- `select`: Fields to return (default: *)
- `order`: Sort order (e.g., `published_at.desc`)
- `limit`: Number of results (default: 20)
- `offset`: Pagination offset
- `category_id`: Filter by category
- `title`: Filter by title (uses ilike)

**Response:**

```json
[
  {
    "id": "uuid",
    "slug": "article-slug",
    "title": "Article Title",
    "content": "Article content...",
    "excerpt": "Brief excerpt...",
    "featured_image": "url",
    "published_at": "2024-01-01T00:00:00Z",
    "category_name": "Technology",
    "author_username": "johndoe"
  }
]
```

#### Create/Update Content

```http
POST /rest/v1/rpc/upsert_content
Content-Type: application/json
Authorization: Bearer your-jwt-token

{
  "title": "New Article",
  "slug": "new-article",
  "content": "Article content...",
  "excerpt": "Brief excerpt...",
  "category_id": "uuid",
  "status": "draft",
  "seo_title": "SEO Title",
  "seo_description": "SEO Description"
}
```

#### Get Categories

```http
GET /rest/v1/categories_with_counts?select=*&is_active=eq.true
```

### Contact Forms

#### Get Public Forms

```http
GET /rest/v1/contact_forms_public?select=*
```

#### Submit Contact Form

```http
POST /rest/v1/rpc/submit_contact_form
Content-Type: application/json

{
  "form_id": "uuid",
  "name": "John Doe",
  "email": "john@example.com",
  "subject": "Inquiry",
  "message": "Message content...",
  "data": {}
}
```

### Launch Campaigns

#### Get Active Campaigns

```http
GET /rest/v1/launch_campaigns_active?select=*
```

#### Subscribe to Campaign

```http
POST /rest/v1/rpc/subscribe_to_campaign
Content-Type: application/json

{
  "campaign_id": "uuid",
  "email": "subscriber@example.com",
  "first_name": "Jane",
  "last_name": "Doe",
  "referral_code": "REF123"
}
```

#### Unsubscribe

```http
POST /rest/v1/rpc/unsubscribe
Content-Type: application/json

{
  "token": "unsubscribe-token"
}
```

### System

#### Get System Stats (Admin Only)

```http
GET /rest/v1/rpc/get_system_stats
Authorization: Bearer admin-jwt-token
```

#### Global Search

```http
POST /rest/v1/rpc/global_search
Content-Type: application/json

{
  "query": "search term",
  "limit": 10
}
```

## Realtime Subscriptions

### Connect to Realtime

```javascript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Subscribe to content updates
const contentChannel = supabase
  .channel('content-updates')
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'content',
      table: 'pages',
    },
    (payload) => {
      console.log('Content update:', payload);
    }
  )
  .subscribe();

// Subscribe to contact form submissions
const contactChannel = supabase
  .channel('contact-submissions')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'contact',
      table: 'contact_inquiries',
    },
    (payload) => {
      console.log('New inquiry:', payload);
    }
  )
  .subscribe();
```

## File Storage

### Upload File

```javascript
const { data, error } = await supabase.storage
  .from('media-files')
  .upload('path/to/file.jpg', file, {
    cacheControl: '3600',
    upsert: false,
  });
```

### Get Public URL

```javascript
const { data } = supabase.storage
  .from('media-files')
  .getPublicUrl('path/to/file.jpg');
```

### List Files

```javascript
const { data, error } = await supabase.storage
  .from('media-files')
  .list('folder', {
    limit: 100,
    offset: 0,
  });
```

## Error Responses

### Standard Error Format

```json
{
  "error": {
    "message": "Error description",
    "details": "Additional details",
    "code": "ERROR_CODE"
  }
}
```

### Common Error Codes

- `401` - Authentication required
- `403` - Insufficient permissions
- `404` - Resource not found
- `409` - Conflict (duplicate entry)
- `422` - Validation error
- `429` - Rate limit exceeded
- `500` - Internal server error

## Rate Limiting

- **Anonymous users**: 100 requests per minute
- **Authenticated users**: 1000 requests per minute
- **Service role**: Unlimited

## Pagination

Use `limit` and `offset` parameters:

```http
GET /rest/v1/content_published?limit=20&offset=40
```

Or use range headers:

```http
GET /rest/v1/content_published
Range: 0-19
```

Response includes count header:

```http
Content-Range: 0-19/100
```

## Filtering

### Exact Match

```http
GET /rest/v1/pages?status=eq.published
```

### Pattern Matching

```http
GET /rest/v1/pages?title=ilike.*search*
```

### Comparison

```http
GET /rest/v1/pages?created_at=gte.2024-01-01
```

### Multiple Filters

```http
GET /rest/v1/pages?status=eq.published&category_id=eq.uuid
```

## Ordering

```http
GET /rest/v1/pages?order=created_at.desc,title.asc
```

## Selecting Fields

```http
GET /rest/v1/pages?select=id,title,slug,author:users(username)
```

## Embedding Relations

```http
GET /rest/v1/pages?select=*,category(*),author:users(*)
```

## SDK Examples

### JavaScript/TypeScript

```javascript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  'http://localhost:9002',
  'your-anon-key'
);

// Fetch published content
const { data, error } = await supabase
  .from('content_published')
  .select('*')
  .order('published_at', { ascending: false })
  .limit(10);

// Submit contact form
const { data, error } = await supabase
  .rpc('submit_contact_form', {
    form_id: 'uuid',
    name: 'John Doe',
    email: 'john@example.com',
    message: 'Hello!',
  });
```

### Python

```python
from supabase import create_client

supabase = create_client(
    "http://localhost:9002",
    "your-anon-key"
)

# Fetch published content
data = supabase.table('content_published').select("*").execute()

# Submit contact form
data = supabase.rpc('submit_contact_form', {
    'form_id': 'uuid',
    'name': 'John Doe',
    'email': 'john@example.com',
    'message': 'Hello!'
}).execute()
```

## Testing

Use the provided test suite:

```bash
npm test
```

Or test individual endpoints:

```bash
curl -X GET \
  'http://localhost:9002/rest/v1/content_published?select=*&limit=5' \
  -H 'apikey: your-anon-key'
```

## Migration Guide

### From Direct Database to Supabase API

1. Replace direct database queries with API calls
2. Update authentication to use JWT tokens
3. Implement real-time subscriptions for live updates
4. Use Row Level Security for fine-grained access control
5. Migrate file uploads to Supabase Storage

## Security Best Practices

1. Always use HTTPS in production
2. Rotate API keys regularly
3. Implement proper RLS policies
4. Validate all input data
5. Use service role keys only on server-side
6. Never expose service role keys to clients
7. Implement rate limiting
8. Monitor API usage and logs

## Support

For issues or questions, please refer to:

- [Supabase Documentation](https://supabase.com/docs)
- [API Status Page](http://localhost:9000/status)
- [GitHub Issues](https://github.com/your-repo/issues)