# Dink House Database

A modular PostgreSQL database setup with Docker, designed for easy local development and seamless migration to Supabase or any PostgreSQL hosting service.

## Features

- 🐳 **Docker-based** - Fully containerized PostgreSQL setup
- 📦 **Modular Schema** - Well-organized SQL modules for different domains
- 🔐 **Authentication System** - Built-in user management with roles and sessions
- 📝 **Content Management** - Pages, categories, and media management
- 📧 **Contact Management** - Form submissions and inquiry tracking
- 🚀 **Launch Campaigns** - Subscriber management and notifications
- 🎛️ **System Settings** - Configurable settings and feature flags
- 🚀 **Supabase Studio** - Modern database management interface
- 🔌 **Kong API Gateway** - RESTful API access to your database
- 🌱 **Seed Data** - Pre-configured development data

## Quick Start

### Prerequisites
- Docker and Docker Compose installed
- Git (optional, for version control)

### Installation

1. **Clone or create the directory:**
   ```bash
   cd dink-house-db
   ```

2. **Copy the environment file:**
   ```bash
   cp .env.local .env
   ```

3. **Start the database:**
   ```bash
   docker-compose up -d
   ```

4. **Wait for initialization (first run only):**
   The database will automatically initialize with all schemas and seed data.

### Access

- **PostgreSQL Database:**
  - Host: `localhost`
  - Port: `9432`
  - Database: `dink_house`
  - Username: `postgres`
  - Password: `DevPassword123!`

- **Supabase Studio:**
  - URL: http://localhost:9000
  - No login required (local development)
  - Full database management interface
  - Table editor, SQL editor, and API documentation

- **Kong API Gateway:**
  - URL: http://localhost:9002
  - Provides REST API access to your database
  - Anon Key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` (see .env)

### Default Users

All default users have the password: `DevPassword123!`

| Username | Email | Role |
|----------|-------|------|
| admin | admin@dinkhouse.com | super_admin |
| editor | editor@dinkhouse.com | editor |
| viewer | viewer@dinkhouse.com | viewer |
| john.doe | john.doe@example.com | admin |
| jane.smith | jane.smith@example.com | editor |

## Project Structure

```
dink-house-db/
├── docker-compose.yml       # Docker Compose configuration
├── Dockerfile              # PostgreSQL Docker image
├── kong.yml               # Kong API Gateway configuration
├── .env.local             # Environment variables template
├── .gitignore            # Git ignore rules
├── README.md             # This file
└── sql/                  # SQL scripts
    ├── init.sh          # Initialization script
    ├── modules/         # Modular schema files
    │   ├── 01-extensions.sql     # PostgreSQL extensions
    │   ├── 02-auth.sql          # Authentication tables
    │   ├── 03-content.sql       # Content management
    │   ├── 04-contact.sql       # Contact management
    │   ├── 05-launch.sql        # Launch campaigns
    │   ├── 06-system.sql        # System settings
    │   └── 07-functions.sql     # Functions and triggers
    └── seeds/           # Seed data for development
        ├── 01-users.sql         # Default users
        ├── 02-content.sql       # Sample content
        ├── 03-system.sql        # System settings
        └── 04-sample-data.sql   # Sample data

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

### Start the database
```bash
docker-compose up -d
```

### Stop the database
```bash
docker-compose down
```

### View logs
```bash
docker-compose logs -f postgres
```

### Connect via psql
```bash
docker exec -it dink-house-db psql -U postgres -d dink_house
```

### Backup database
```bash
docker exec dink-house-db pg_dump -U postgres dink_house > backup.sql
```

### Restore database
```bash
docker exec -i dink-house-db psql -U postgres dink_house < backup.sql
```

### Reset database (Warning: Deletes all data!)
```bash
docker-compose down -v
docker-compose up -d
```

## Migration to Production

### Supabase Migration

1. **Export schema:**
   ```bash
   docker exec dink-house-db pg_dump -U postgres --schema-only dink_house > schema.sql
   ```

2. **Create Supabase project** at https://app.supabase.com

3. **Connect to Supabase:**
   ```bash
   psql -h [your-project].supabase.co -p 5432 -d postgres -U postgres
   ```

4. **Import schema:**
   ```bash
   psql -h [your-project].supabase.co -p 5432 -d postgres -U postgres < schema.sql
   ```

### Other PostgreSQL Hosts

The database is compatible with any PostgreSQL 15+ hosting service:
- AWS RDS
- Google Cloud SQL
- Azure Database
- DigitalOcean Managed Databases
- Heroku Postgres

Simply use the backup/restore commands above with your production connection string.

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

⚠️ **For Development Only**: The default passwords and settings are for local development only. Before deploying to production:

1. Change all default passwords
2. Update JWT secret
3. Configure proper SMTP settings
4. Enable SSL/TLS
5. Set up proper firewall rules
6. Implement backup strategy
7. Configure monitoring

## Troubleshooting

### Port Already in Use
Change the port in `.env`:
```env
DB_PORT=5433
PGADMIN_PORT=5051
```

### Permission Denied
Ensure Docker has proper permissions:
```bash
sudo chmod +x sql/init.sh
```

### Slow Initialization
First-time setup may take 1-2 minutes. Check logs:
```bash
docker-compose logs -f postgres
```

### Supabase Studio Connection Issues
If Studio doesn't connect:
1. Ensure PostgreSQL is healthy: `docker compose ps`
2. Check pg-meta logs: `docker compose logs pg-meta`
3. Restart services: `docker compose restart`

### Kong API Gateway Issues
For API access problems:
1. Check Kong is running: `docker compose logs kong`
2. Verify API keys in `.env` file
3. Test with: `curl http://localhost:9002/rest/v1/`

## License

This project is designed as a template for development. Feel free to modify and use as needed.

## Support

For issues or questions, please check the Docker and PostgreSQL documentation or create an issue in your project repository.