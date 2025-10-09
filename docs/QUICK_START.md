# Dink House Contact System - Quick Start Guide

## ✅ Current Status

Your system is configured and ready! Here's what's set up:

- ✅ **PostgreSQL Database**: Running with all migrations applied
- ✅ **SendGrid API**: Valid API key configured
- ✅ **Supabase Studio**: Running at http://localhost:9000
- ✅ **Kong API Gateway**: Running at http://localhost:9002
- ✅ **Email Templates**: 3 templates installed in database
- ✅ **Security Middleware**: Rate limiting and validation configured

## 🚀 Quick Start Steps

### Step 1: Create Storage Bucket (One-time setup)

1. Open Supabase Studio: http://localhost:9000
2. Click on "Storage" in the left sidebar
3. Click "New bucket"
4. Name: `email-assets`
5. Set to "Public bucket" ✅
6. Click "Save"

### Step 2: Upload Logo

1. In Storage, click on the `email-assets` bucket
2. Click "Upload files"
3. Upload your logo as `dink-house-logo.png`
   - Recommended size: 300x100px
   - Format: PNG with transparent background

### Step 3: Start Application Services

Open three terminal windows and run:

**Terminal 1 - Landing Page:**
```bash
cd /home/ert/dink-house/dink-house-landing-dev
npm run dev
```
Access at: http://localhost:3000

**Terminal 2 - Database API:**
```bash
cd /home/ert/dink-house/dink-house-db
npm run dev
```
Runs on: http://localhost:3001

**Terminal 3 - Admin Dashboard:**
```bash
cd /home/ert/dink-house/dink-house-admin
npm run dev
```
Access at: http://localhost:3002

### Step 4: Test the System

```bash
cd /home/ert/dink-house
source .env.test
node test-contact-system.js --all
```

## 📧 Testing Contact Form

### Option 1: Via Landing Page UI
1. Visit http://localhost:3000/contact
2. Fill out the form
3. Submit

### Option 2: Via API
```bash
curl -X POST http://localhost:3000/api/contact-form \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "John",
    "lastName": "Doe",
    "email": "john@example.com",
    "message": "Test message from Quick Start"
  }'
```

## 👨‍💼 Admin Dashboard

1. Visit http://localhost:3002/contact-inquiries
2. View all contact form submissions
3. Click "View" to see details
4. Update status and send responses

## 🔍 Monitor Emails

### Check Database Logs:
```bash
docker exec dink-house-db psql -U postgres -d dink_house \
  -c "SELECT * FROM system.email_logs ORDER BY created_at DESC LIMIT 5;"
```

### Check Contact Inquiries:
```bash
docker exec dink-house-db psql -U postgres -d dink_house \
  -c "SELECT * FROM contact.contact_inquiries ORDER BY created_at DESC LIMIT 5;"
```

## 📝 Important URLs

- **Landing Page**: http://localhost:3000
- **Admin Dashboard**: http://localhost:3002
- **Supabase Studio**: http://localhost:9000
- **Kong API**: http://localhost:9002
- **Contact Form**: http://localhost:3000/contact
- **Contact Management**: http://localhost:3002/contact-inquiries

## 🚨 Troubleshooting

If tests fail:

1. **Check services are running:**
   ```bash
   ./check-system-status.sh
   ```

2. **Restart database if needed:**
   ```bash
   cd dink-house-db
   docker-compose restart
   ```

3. **Check logs:**
   ```bash
   docker-compose logs -f
   ```

## 📧 Email Configuration

Your SendGrid is configured with:
- **From**: contact@dinkhousepb.com
- **Admin**: contact@dinkhousepb.com
- **API Key**: Valid and working ✅

## 🎉 You're Ready!

The contact form system is fully configured and ready to use. Start the services and test the contact form!