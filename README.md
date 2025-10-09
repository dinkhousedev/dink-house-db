# Dink House Database

A modular PostgreSQL database setup powered by **Supabase Cloud**, with Express.js API for custom backend functionality.

## Features

- ☁️ **Cloud-Hosted** - Runs on Supabase Cloud (PostgreSQL)
- 📦 **Modular Schema** - Well-organized SQL modules for different domains
- 🔐 **Authentication System** - Supabase Auth with JWT tokens
- 📝 **Content Management** - Pages, categories, and media management
- 📧 **Contact Management** - Form submissions and inquiry tracking
- 🚀 **Launch Campaigns** - Subscriber management and notifications
- 🎛️ **System Settings** - Configurable settings and feature flags
- 🚀 **Supabase Dashboard** - Modern cloud database management interface
- 🔌 **Express API** - Custom REST API for backend operations
- 🌱 **Seed Data** - Pre-configured development data

## Quick Start

### Prerequisites
- Node.js 18+ installed
- Access to Supabase Cloud project

### Installation

1. **Navigate to the directory:**
   ```bash
   cd dink-house-db
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Configure environment:**
   The `.env.local` file is already configured for Supabase Cloud:
   ```env
   SUPABASE_URL=https://wchxzbuuwssrnaxshseu.supabase.co
   SUPABASE_ANON_KEY=your-anon-key
   SUPABASE_SERVICE_KEY=your-service-key
   ```

4. **Start the API server:**
   ```bash
   npm run dev
   ```

### Access

- **Supabase Cloud:**
  - Project URL: `https://wchxzbuuwssrnaxshseu.supabase.co`
  - Dashboard: `https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu`

- **Express API (Local):**
  - URL: `http://localhost:3003`
  - Provides custom REST API endpoints
  - Connects to Supabase Cloud database

- **Database Direct Connection:**
  - Host: `aws-1-us-east-2.pooler.supabase.com`
  - Port: `5432`
  - Database: `postgres`
  - Username: `postgres.wchxzbuuwssrnaxshseu`
  - Password: (from environment variables)

## Project Structure

```
dink-house-db/
├── api/                  # Express.js API server
│   ├── index.js         # Main API entry point
│   ├── config/          # Configuration files
│   ├── routes/          # API route handlers
│   └── middleware/      # Express middleware
├── sql/                 # SQL scripts and migrations
│   ├── modules/         # Modular schema files (00-25)
│   └── seeds/           # Seed data for development
├── scripts/             # Utility scripts
├── .env.local          # Environment variables (cloud config)
├── .env.example        # Environment template
├── package.json        # Node.js dependencies
└── README.md           # This file
```

## Database Schema

The database uses **separate schemas** for better organization and security:

### Schema Organization

| Schema | Purpose | Key Tables |
|--------|---------|------------|
| **auth** | Authentication & authorization | users, sessions, api_keys, refresh_tokens |
| **content** | Content management | categories, pages, media_files, revisions |
| **contact** | Contact & inquiries | contact_forms, contact_inquiries, contact_responses |
| **launch** | Campaigns & notifications | launch_campaigns, launch_subscribers, notification_templates |
| **system** | System configuration | system_settings, activity_logs, system_jobs, feature_flags |
| **api** | API views & functions | (For future REST API views) |
| **public** | Extensions & utilities | PostgreSQL extensions (uuid-ossp, pgcrypto, citext) |

### Security Roles

The database includes predefined roles for access control:

- **app_anon** - Anonymous/public access (read public content, submit forms)
- **app_user** - Authenticated users (manage own content)
- **app_admin** - Administrators (full access except system)
- **app_service** - Service accounts (unrestricted access)

Row Level Security (RLS) is enabled on sensitive tables for fine-grained access control.

## Common Commands

### Start API server (development)
```bash
npm run dev
```

### Start API server (production)
```bash
npm run start
```

### Run tests
```bash
npm test
```

### Database migrations
```bash
npm run db:migrate
```

### Seed database
```bash
npm run db:seed
```

### Create admin user
```bash
npm run admin:create
```

### Connect via psql (Cloud)
```bash
psql postgresql://postgres.wchxzbuuwssrnaxshseu:[PASSWORD]@aws-1-us-east-2.pooler.supabase.com:5432/postgres
```

### Backup database (via Supabase CLI)
```bash
supabase db dump -f backup.sql --project-ref wchxzbuuwssrnaxshseu
```

## Cloud Database Management

### Already Using Supabase Cloud

This project is **already configured** to use Supabase Cloud. All database operations run against the cloud instance.

### Managing Database via Supabase Dashboard

Access the Supabase Dashboard for:
- **Table Editor**: View and edit data directly
- **SQL Editor**: Run custom queries
- **Database Settings**: Manage users, roles, and policies
- **Logs**: View database logs and activity
- **Storage**: Manage file uploads

Dashboard URL: `https://supabase.com/dashboard/project/wchxzbuuwssrnaxshseu`

### Schema Migrations

All schema changes should be applied via SQL Editor in Supabase Dashboard or using migration scripts in `sql/modules/`.

**Important**: Always backup before applying schema changes in production.

## Development Tips

### Adding New Tables

1. Create a new migration file in `sql/modules/`
2. Follow the naming convention: `XX-module-name.sql`
3. Include indexes and constraints
4. Add triggers if needed

### Modifying Existing Schema

1. Create a new migration file
2. Use `ALTER TABLE` statements
3. Update seed data if necessary

### Custom Functions

Add custom PostgreSQL functions in `sql/modules/07-functions.sql` or create a new functions file.

## Security Notes

⚠️ **Production Environment**: This project uses Supabase Cloud which includes:

- ✅ SSL/TLS enabled by default
- ✅ Automatic backups
- ✅ Row Level Security (RLS) policies
- ✅ JWT authentication
- ✅ Built-in monitoring

**Important Security Tasks:**
1. Keep API keys secure (never commit to git)
2. Rotate keys periodically in Supabase Dashboard
3. Review and update RLS policies regularly
4. Monitor database activity via Dashboard
5. Use service role key only on backend (never expose to clients)

## Troubleshooting

### API Connection Issues
If the Express API can't connect to Supabase:
1. Verify environment variables in `.env.local`
2. Check Supabase project status in Dashboard
3. Ensure API keys are valid and not expired
4. Test connection: `curl https://wchxzbuuwssrnaxshseu.supabase.co`

### Database Access Issues
If you can't access the database:
1. Check database credentials in `.env.local`
2. Verify IP is allowed in Supabase Dashboard > Settings > Database
3. Use connection pooler URL for better performance
4. Check Supabase status: https://status.supabase.com

### Rate Limiting
If you hit rate limits:
1. Review your query patterns
2. Implement proper caching
3. Consider upgrading Supabase plan if needed
4. Use connection pooling

### Migration Issues
If migrations fail:
1. Check SQL syntax in migration files
2. Verify user permissions in Supabase
3. Run migrations one at a time
4. Check logs in Supabase Dashboard

## License

This project is designed as a template for development. Feel free to modify and use as needed.

## Support

For issues or questions, please check the Docker and PostgreSQL documentation or create an issue in your project repository.