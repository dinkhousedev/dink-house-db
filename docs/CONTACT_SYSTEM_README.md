# Dink House Contact Form System - Complete Implementation Guide

## Overview

The Dink House Contact Form System is a comprehensive solution that integrates SendGrid email delivery with a multi-tier architecture consisting of:

- **Landing Page** (Next.js) - Public-facing contact form
- **Database API** (Express.js) - Centralized API with PostgreSQL storage
- **Admin Dashboard** (Next.js) - Contact inquiry management interface
- **Email Service** (SendGrid) - Branded email notifications

## Features

### Core Functionality
- ✅ Contact form submission with validation
- ✅ SendGrid email integration with branded templates
- ✅ Admin dashboard for managing inquiries
- ✅ Rate limiting and security measures
- ✅ Email delivery tracking and logs
- ✅ Supabase Storage for email assets

### Security Features
- 🔒 Rate limiting (5 requests per minute per IP)
- 🔒 Input sanitization and validation
- 🔒 CSRF protection
- 🔒 XSS prevention
- 🔒 SQL injection protection
- 🔒 CORS configuration

## Quick Start

### 1. Run Setup Script

```bash
./setup-contact-system.sh
```

This will:
- Check prerequisites
- Install dependencies
- Apply database migrations
- Configure environment variables
- Create test configuration

### 2. Manual Configuration

If you prefer manual setup:

#### Install Dependencies

```bash
# Landing Page
cd dink-house-landing-dev
npm install @sendgrid/mail

# Database API
cd ../dink-house-db
npm install express-rate-limit helmet express-validator

# Admin Dashboard
cd ../dink-house-admin
npm install @sendgrid/mail date-fns
```

#### Apply Database Migrations

```bash
# Apply email system schema
docker exec -i dink-house-db psql -U postgres -d dink_house < dink-house-db/sql/modules/15-email-system.sql

# Apply storage setup
docker exec -i dink-house-db psql -U postgres -d dink_house < dink-house-db/sql/modules/16-storage-setup.sql
```

### 3. Configure SendGrid

1. **Get API Key**
   - Log in to [SendGrid Dashboard](https://app.sendgrid.com)
   - Go to Settings → API Keys
   - Create new key with Mail Send permissions

2. **Verify Domain**
   - Settings → Sender Authentication
   - Authenticate your domain
   - Add DNS records to your provider

3. **Create Sender Identity**
   - Single Sender Verification
   - Add hello@dinkhousepb.com

### 4. Upload Logo to Supabase

1. Go to Supabase Dashboard
2. Navigate to Storage
3. Create bucket `email-assets` (public)
4. Upload `dink-house-logo.png`

### 5. Environment Variables

Create `.env.local` files in each project with:

```env
# SendGrid
SENDGRID_API_KEY=SG.your_key_here
EMAIL_FROM=hello@dinkhousepb.com
EMAIL_FROM_NAME=The Dink House
ADMIN_EMAIL=admin@dinkhousepb.com

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key

# Site
SITE_URL=https://dinkhousepb.com
```

## Testing

### Run Comprehensive Test Suite

```bash
# Run all tests
node test-contact-system.js --all

# Run specific tests
node test-contact-system.js --sendgrid    # Test SendGrid only
node test-contact-system.js --submit      # Test form submission
node test-contact-system.js --rate-limit  # Test rate limiting
node test-contact-system.js --storage     # Test Supabase storage

# Interactive mode
node test-contact-system.js --interactive
```

### Manual Testing

1. **Submit Contact Form**
   ```bash
   curl -X POST http://localhost:3000/api/contact-form \
     -H "Content-Type: application/json" \
     -d '{
       "firstName": "Test",
       "lastName": "User",
       "email": "test@example.com",
       "message": "Test message"
     }'
   ```

2. **Check Admin Dashboard**
   - Navigate to http://localhost:3002/contact-inquiries
   - View and manage submissions
   - Send responses

## API Endpoints

### Landing Page
- `POST /api/contact-form` - Submit contact form

### Database API
- `POST /api/contact` - Create contact inquiry
- `GET /api/contact/submissions` - List all inquiries
- `GET /api/contact/submissions/:id` - Get specific inquiry
- `PATCH /api/contact/submissions/:id` - Update inquiry status

### Admin Dashboard
- `POST /api/send-response` - Send email response

## File Structure

```
dink-house/
├── dink-house-landing-dev/
│   ├── pages/api/
│   │   └── contact-form.ts         # Contact form API with SendGrid
│   └── components/
│       └── contact-form.tsx        # Contact form UI
├── dink-house-db/
│   ├── api/
│   │   ├── routes/
│   │   │   └── contact.js          # Contact API routes
│   │   └── middleware/
│   │       └── security.js         # Security middleware
│   └── sql/modules/
│       ├── 15-email-system.sql     # Email system schema
│       └── 16-storage-setup.sql    # Storage configuration
├── dink-house-admin/
│   ├── app/api/send-response/
│   │   └── route.ts                # Admin response API
│   ├── app/contact-inquiries/
│   │   └── page.tsx                # Inquiries page
│   └── components/dashboard/
│       └── ContactInquiriesTable.tsx  # Inquiries management
├── test-contact-system.js          # Comprehensive test suite
├── setup-contact-system.sh         # Setup script
└── CONTACT_SYSTEM_README.md        # This file
```

## Email Templates

The system includes three email templates stored in the database:

1. **contact_form_thank_you** - Sent to users after submission
2. **contact_form_admin** - Sent to admin with inquiry details
3. **welcome_email** - Welcome message for new users

Templates support variables like:
- `{{first_name}}` - User's first name
- `{{logo_url}}` - Dink House logo URL
- `{{site_url}}` - Website URL
- `{{message}}` - User's message

## Monitoring

### Email Logs

View email logs in the database:

```sql
-- Recent emails
SELECT * FROM system.email_logs
ORDER BY created_at DESC
LIMIT 10;

-- Failed emails
SELECT * FROM system.email_logs
WHERE status = 'failed';

-- Contact submissions
SELECT * FROM contact.contact_inquiries
ORDER BY created_at DESC;
```

### SendGrid Dashboard

Monitor delivery in SendGrid:
- Activity → Activity Feed - View email status
- Stats → Overview - Delivery metrics
- Suppressions → Blocks - Check blocked emails

## Troubleshooting

### Common Issues

1. **"SendGrid API key not configured"**
   - Verify API key in .env files
   - Check key has Mail Send permissions

2. **"Rate limit exceeded"**
   - Wait 60 seconds between submissions
   - Adjust limits in middleware/security.js

3. **"Logo not showing in emails"**
   - Upload logo to Supabase Storage
   - Verify bucket is public
   - Check URL in email templates

4. **"Emails not received"**
   - Check spam folder
   - Verify domain authentication
   - Review SendGrid activity logs

### Debug Commands

```bash
# Check database connection
docker exec dink-house-db psql -U postgres -d dink_house -c "SELECT 1"

# View recent submissions
docker exec dink-house-db psql -U postgres -d dink_house -c "SELECT * FROM contact.contact_inquiries ORDER BY created_at DESC LIMIT 5"

# Check email logs
docker exec dink-house-db psql -U postgres -d dink_house -c "SELECT * FROM system.email_logs ORDER BY created_at DESC LIMIT 5"

# Test SendGrid connection
curl -X GET https://api.sendgrid.com/v3/user/profile \
  -H "Authorization: Bearer YOUR_API_KEY"
```

## Security Considerations

1. **Never commit API keys** - Use environment variables
2. **Implement rate limiting** - Prevent abuse
3. **Validate all inputs** - Prevent injection attacks
4. **Use HTTPS in production** - Encrypt data in transit
5. **Monitor for anomalies** - Check logs regularly
6. **Keep dependencies updated** - Regular security patches

## Production Deployment

### Environment Variables

Set in production:

```bash
NODE_ENV=production
SENDGRID_API_KEY=SG.production_key
SUPABASE_URL=https://production.supabase.co
SUPABASE_SERVICE_KEY=production_service_key
RATE_LIMIT_PER_MINUTE=3
RATE_LIMIT_PER_HOUR=20
```

### DNS Configuration

Add to your DNS provider:

```
SPF: v=spf1 include:sendgrid.net ~all
DKIM: [Provided by SendGrid]
DMARC: v=DMARC1; p=none; rua=mailto:admin@dinkhousepb.com
```

### Monitoring Setup

1. **SendGrid Webhooks** - Track delivery events
2. **Error Tracking** - Sentry or similar
3. **Uptime Monitoring** - Monitor API endpoints
4. **Log Aggregation** - Centralize logs

## Support

For issues or questions:

1. Check test results: `node test-contact-system.js --all`
2. Review logs in database
3. Check SendGrid activity feed
4. Verify environment configuration

## Version History

- **v1.0.0** - Initial implementation with SendGrid integration
- Supports contact form submission
- Admin dashboard for inquiry management
- Email delivery tracking
- Rate limiting and security

---

© 2025 The Dink House - Where Pickleball Lives