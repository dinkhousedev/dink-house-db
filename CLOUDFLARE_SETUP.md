# Cloudflare Tunnel Setup for Supabase

## Quick Setup

### 1. Create Cloudflare Tunnel
```bash
# Install cloudflared
brew install cloudflare/cloudflare/cloudflared

# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create dink-house-db

# Get tunnel credentials (save the JSON output)
cloudflared tunnel info dink-house-db
```

### 2. Update Configuration
Edit `cloudflare-tunnel.yml`:
- Replace `YOUR_TUNNEL_ID` with your tunnel ID
- Replace `yourdomain.com` with your domain

### 3. Add DNS Records in Cloudflare
```
api.yourdomain.com -> CNAME -> YOUR_TUNNEL_ID.cfargotunnel.com
db.yourdomain.com -> CNAME -> YOUR_TUNNEL_ID.cfargotunnel.com
```

### 4. Run with Docker Compose
```bash
# Add tunnel token to .env
echo "CLOUDFLARE_TUNNEL_TOKEN=your_token_here" >> .env

# Start services with Cloudflare tunnel
docker-compose -f docker-compose.yml -f docker-compose.cloudflare.yml up -d
```

## Exposed Services

| Service | URL | Port | Description |
|---------|-----|------|-------------|
| API | api.yourdomain.com | 9002 | Supabase REST API |
| Database | db.yourdomain.com | 9432 | PostgreSQL direct connection |

## Security Notes

- API is publicly accessible (protected by Supabase keys)
- Database requires PostgreSQL client with credentials
- Use Row Level Security (RLS) in Supabase for data protection
- Rotate your tunnel token regularly

## Connection Examples

### API Connection
```javascript
const SUPABASE_URL = 'https://api.yourdomain.com'
const SUPABASE_ANON_KEY = 'your-anon-key'
```

### Database Connection
```bash
psql postgresql://postgres:DevPassword123!@db.yourdomain.com:9432/dink_house
```

## Troubleshooting

### Check tunnel status
```bash
docker logs cloudflared-tunnel
```

### Restart tunnel
```bash
docker-compose -f docker-compose.cloudflare.yml restart cloudflared
```

### View active connections
```bash
cloudflared tunnel info dink-house-db
```