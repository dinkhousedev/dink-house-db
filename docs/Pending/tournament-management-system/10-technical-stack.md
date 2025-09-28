# Technical Stack & Deployment Architecture

## Technology Stack Overview

### Core Technologies

```javascript
const techStack = {
  frontend: {
    framework: 'Next.js 15.3.1',
    ui: 'HeroUI v2',
    language: 'TypeScript 5.6',
    styling: 'Tailwind CSS 4',
    state: 'Zustand',
    forms: 'React Hook Form + Zod',
    animation: 'Framer Motion',
    charts: 'Recharts'
  },

  backend: {
    runtime: 'Node.js 20 LTS',
    framework: 'Express.js 4.18',
    database: 'PostgreSQL 15',
    orm: 'Supabase Client',
    validation: 'Zod',
    auth: 'Supabase Auth',
    realtime: 'Supabase Realtime + Socket.io'
  },

  infrastructure: {
    hosting: 'Vercel + Supabase',
    cdn: 'Cloudflare',
    storage: 'Supabase Storage',
    monitoring: 'Sentry + Datadog',
    ci_cd: 'GitHub Actions',
    containerization: 'Docker'
  },

  services: {
    email: 'SendGrid',
    sms: 'Twilio',
    payment: 'Stripe',
    search: 'Algolia',
    analytics: 'PostHog',
    maps: 'Mapbox'
  }
};
```

## Frontend Architecture

### Next.js Application Structure

```
dink-house-tournament/
├── app/                          # Next.js 15 App Router
│   ├── (auth)/                  # Auth group
│   │   ├── login/
│   │   ├── register/
│   │   └── reset-password/
│   │
│   ├── (dashboard)/             # Protected routes
│   │   ├── director/           # Tournament director
│   │   ├── player/            # Player portal
│   │   ├── staff/             # Staff interface
│   │   └── admin/             # System admin
│   │
│   ├── (public)/               # Public routes
│   │   ├── tournaments/
│   │   ├── live/
│   │   └── results/
│   │
│   ├── api/                    # API routes
│   │   ├── tournaments/
│   │   ├── webhooks/
│   │   └── internal/
│   │
│   └── layout.tsx              # Root layout
│
├── components/                  # React components
│   ├── tournament/
│   ├── bracket/
│   ├── scoring/
│   ├── shared/
│   └── ui/                    # HeroUI components
│
├── lib/                        # Utilities
│   ├── supabase/
│   ├── api/
│   ├── utils/
│   └── hooks/
│
├── styles/                     # Global styles
├── public/                     # Static assets
└── config/                     # Configuration
```

### Component Architecture

```typescript
// Example: Tournament Card Component
interface TournamentCardProps {
  tournament: Tournament;
  onRegister?: () => void;
  variant?: 'compact' | 'full';
}

export const TournamentCard: FC<TournamentCardProps> = ({
  tournament,
  onRegister,
  variant = 'compact'
}) => {
  const { user } = useAuth();
  const { register, loading } = useTournamentRegistration();

  return (
    <Card className={cn('tournament-card', variant)}>
      <CardHeader>
        <h3>{tournament.name}</h3>
        <Badge>{tournament.status}</Badge>
      </CardHeader>

      <CardBody>
        <TournamentDetails tournament={tournament} />
        {variant === 'full' && (
          <DivisionList divisions={tournament.divisions} />
        )}
      </CardBody>

      <CardFooter>
        <Button
          onClick={() => register(tournament.id)}
          disabled={!canRegister(tournament, user)}
          loading={loading}
        >
          Register
        </Button>
      </CardFooter>
    </Card>
  );
};
```

### State Management with Zustand

```typescript
// Tournament Store
interface TournamentStore {
  tournaments: Tournament[];
  selectedTournament: Tournament | null;
  filters: TournamentFilters;
  loading: boolean;

  // Actions
  fetchTournaments: () => Promise<void>;
  selectTournament: (id: string) => void;
  updateFilters: (filters: Partial<TournamentFilters>) => void;
  createTournament: (data: CreateTournamentDTO) => Promise<Tournament>;
}

export const useTournamentStore = create<TournamentStore>((set, get) => ({
  tournaments: [],
  selectedTournament: null,
  filters: defaultFilters,
  loading: false,

  fetchTournaments: async () => {
    set({ loading: true });
    try {
      const data = await api.tournaments.list(get().filters);
      set({ tournaments: data, loading: false });
    } catch (error) {
      set({ loading: false });
      throw error;
    }
  },

  selectTournament: (id) => {
    const tournament = get().tournaments.find(t => t.id === id);
    set({ selectedTournament: tournament });
  },

  // ... other actions
}));
```

## Backend Architecture

### API Structure

```
dink-house-api/
├── src/
│   ├── app.ts                 # Express app setup
│   ├── server.ts              # Server entry point
│   │
│   ├── routes/                # API routes
│   │   ├── auth.routes.ts
│   │   ├── tournament.routes.ts
│   │   ├── team.routes.ts
│   │   ├── match.routes.ts
│   │   └── payment.routes.ts
│   │
│   ├── controllers/           # Route handlers
│   │   ├── tournament.controller.ts
│   │   └── ...
│   │
│   ├── services/              # Business logic
│   │   ├── tournament.service.ts
│   │   ├── bracket.service.ts
│   │   ├── payment.service.ts
│   │   └── notification.service.ts
│   │
│   ├── models/                # Data models
│   │   ├── tournament.model.ts
│   │   └── ...
│   │
│   ├── middleware/            # Express middleware
│   │   ├── auth.middleware.ts
│   │   ├── validation.middleware.ts
│   │   ├── rateLimit.middleware.ts
│   │   └── error.middleware.ts
│   │
│   ├── utils/                 # Utilities
│   │   ├── database.ts
│   │   ├── logger.ts
│   │   └── validators.ts
│   │
│   └── config/                # Configuration
│       ├── database.config.ts
│       └── app.config.ts
│
├── tests/                     # Test files
├── migrations/                # Database migrations
└── scripts/                   # Utility scripts
```

### Service Layer Example

```typescript
// Tournament Service
export class TournamentService {
  constructor(
    private db: SupabaseClient,
    private bracketService: BracketService,
    private notificationService: NotificationService
  ) {}

  async createTournament(data: CreateTournamentDTO, userId: string) {
    // Begin transaction
    const { data: tournament, error } = await this.db
      .from('tournaments')
      .insert({
        ...data,
        created_by: userId,
        status: 'draft'
      })
      .select()
      .single();

    if (error) throw new AppError('Failed to create tournament', 500);

    // Create default divisions if template provided
    if (data.templateId) {
      await this.createDivisionsFromTemplate(tournament.id, data.templateId);
    }

    // Setup communication templates
    await this.setupCommunicationTemplates(tournament.id);

    // Log activity
    await this.logActivity('tournament_created', tournament);

    return tournament;
  }

  async generateBrackets(tournamentId: string, divisionId: string) {
    // Get teams
    const teams = await this.getConfirmedTeams(divisionId);

    // Generate bracket structure
    const bracket = await this.bracketService.generate({
      teams,
      type: 'double_elimination',
      seedingMethod: 'dupr'
    });

    // Create matches
    const matches = await this.createMatchesFromBracket(bracket);

    // Notify teams
    await this.notificationService.notifyBracketRelease(teams, matches);

    return bracket;
  }
}
```

## Database Design

### Supabase Configuration

```typescript
// supabase.config.ts
export const supabaseConfig = {
  url: process.env.SUPABASE_URL!,
  anonKey: process.env.SUPABASE_ANON_KEY!,
  serviceKey: process.env.SUPABASE_SERVICE_KEY!,

  options: {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: true
    },

    realtime: {
      params: {
        eventsPerSecond: 10
      }
    },

    db: {
      schema: 'public'
    }
  }
};

// Database client setup
export const createClient = (accessToken?: string) => {
  const options = { ...supabaseConfig.options };

  if (accessToken) {
    options.global = {
      headers: {
        Authorization: `Bearer ${accessToken}`
      }
    };
  }

  return createSupabaseClient(
    supabaseConfig.url,
    supabaseConfig.anonKey,
    options
  );
};
```

### Database Connection Pooling

```typescript
// Connection pool configuration
const poolConfig = {
  max: 20,                    // Maximum connections
  min: 5,                     // Minimum connections
  idleTimeoutMillis: 30000,  // Close idle connections after 30s
  connectionTimeoutMillis: 2000,
  ssl: {
    rejectUnauthorized: false // For development
  }
};

// Query optimization
const queryConfig = {
  statement_timeout: 10000,   // 10 second timeout
  query_timeout: 10000,
  lock_timeout: 10000,
  idle_in_transaction_session_timeout: 10000
};
```

## Deployment Architecture

### Infrastructure Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         CloudFlare                           │
│                     (CDN & DDoS Protection)                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │                             │
        ▼                             ▼
┌──────────────────┐         ┌──────────────────┐
│     Vercel        │         │    Supabase      │
│   (Frontend)      │ ◄────► │   (Backend)      │
│                   │         │                  │
│  - Next.js App    │         │  - PostgreSQL    │
│  - API Routes     │         │  - Auth          │
│  - Static Assets  │         │  - Realtime      │
│  - Edge Functions │         │  - Storage       │
└──────────────────┘         └──────────────────┘
        │                             │
        └──────────┬──────────────────┘
                   │
        ┌──────────▼──────────────┐
        │   External Services      │
        ├──────────────────────────┤
        │  - Stripe (Payments)     │
        │  - SendGrid (Email)      │
        │  - Twilio (SMS)          │
        │  - DUPR API              │
        │  - Sentry (Monitoring)   │
        └──────────────────────────┘
```

### Vercel Deployment Configuration

```json
{
  "name": "dink-house-tournament",
  "version": 2,
  "builds": [
    {
      "src": "package.json",
      "use": "@vercel/next"
    }
  ],
  "routes": [
    {
      "src": "/api/(.*)",
      "headers": {
        "Cache-Control": "no-cache, no-store, must-revalidate"
      }
    },
    {
      "src": "/(.*)",
      "headers": {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "X-XSS-Protection": "1; mode=block"
      }
    }
  ],
  "env": {
    "NEXT_PUBLIC_SUPABASE_URL": "@supabase_url",
    "NEXT_PUBLIC_SUPABASE_ANON_KEY": "@supabase_anon_key",
    "SUPABASE_SERVICE_KEY": "@supabase_service_key",
    "STRIPE_SECRET_KEY": "@stripe_secret",
    "SENDGRID_API_KEY": "@sendgrid_key"
  },
  "regions": ["iad1"],
  "functions": {
    "app/api/tournaments/[id]/route.ts": {
      "maxDuration": 30
    }
  }
}
```

### Docker Configuration

```dockerfile
# Frontend Dockerfile
FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app

COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules

EXPOSE 3000
CMD ["npm", "start"]
```

### Docker Compose for Development

```yaml
version: '3.8'

services:
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    environment:
      - NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}
      - NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
    depends_on:
      - postgres

  postgres:
    image: supabase/postgres:15
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=tournament_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
```

## Monitoring & Observability

### Logging Strategy

```typescript
// Logger configuration
import winston from 'winston';
import { Logtail } from '@logtail/node';

const logtail = new Logtail(process.env.LOGTAIL_TOKEN);

export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: {
    service: 'tournament-api',
    environment: process.env.NODE_ENV
  },
  transports: [
    new winston.transports.Console({
      format: winston.format.simple()
    }),
    new Logtail.LogtailTransport(logtail)
  ]
});

// Request logging middleware
export const requestLogger = (req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;

    logger.info('Request processed', {
      method: req.method,
      url: req.url,
      status: res.statusCode,
      duration,
      userId: req.user?.id,
      ip: req.ip
    });
  });

  next();
};
```

### Performance Monitoring

```typescript
// Sentry configuration
import * as Sentry from '@sentry/node';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 1.0,

  integrations: [
    new Sentry.Integrations.Http({ tracing: true }),
    new Sentry.Integrations.Express({ app }),
    new Sentry.Integrations.Postgres()
  ],

  beforeSend(event) {
    // Filter sensitive data
    if (event.request?.cookies) {
      delete event.request.cookies;
    }
    return event;
  }
});

// Performance tracking
export const trackPerformance = (operation: string) => {
  const transaction = Sentry.startTransaction({
    op: operation,
    name: operation
  });

  Sentry.getCurrentHub().configureScope(scope =>
    scope.setSpan(transaction)
  );

  return transaction;
};
```

### Health Checks

```typescript
// Health check endpoints
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: process.env.NODE_ENV
  });
});

app.get('/health/detailed', async (req, res) => {
  const checks = {
    database: await checkDatabase(),
    redis: await checkRedis(),
    storage: await checkStorage(),
    email: await checkEmailService(),
    payment: await checkPaymentService()
  };

  const healthy = Object.values(checks).every(c => c.healthy);

  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'healthy' : 'unhealthy',
    checks,
    timestamp: new Date().toISOString()
  });
});
```

## CI/CD Pipeline

### GitHub Actions Workflow

```yaml
name: Deploy Tournament System

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint

      - name: Run type check
        run: npm run type-check

      - name: Run tests
        run: npm test
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test

      - name: Run E2E tests
        run: npm run test:e2e

      - name: Build application
        run: npm run build

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - uses: actions/checkout@v3

      - name: Deploy to Vercel
        uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'

      - name: Run database migrations
        run: |
          npm run migrate:deploy
        env:
          DATABASE_URL: ${{ secrets.PRODUCTION_DATABASE_URL }}

      - name: Notify deployment
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: 'Deployment to production completed'
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

## Security Configuration

### Environment Variables

```bash
# .env.production
# Database
DATABASE_URL=postgresql://user:pass@host:5432/db
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=xxx
SUPABASE_SERVICE_KEY=xxx

# Authentication
JWT_SECRET=xxx
SESSION_SECRET=xxx
REFRESH_TOKEN_SECRET=xxx

# External Services
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
SENDGRID_API_KEY=SG.xxx
TWILIO_ACCOUNT_SID=xxx
TWILIO_AUTH_TOKEN=xxx
DUPR_API_KEY=xxx

# Monitoring
SENTRY_DSN=https://xxx@sentry.io/xxx
LOGTAIL_TOKEN=xxx
DATADOG_API_KEY=xxx

# Security
CORS_ORIGIN=https://dinkhouse.com
RATE_LIMIT_WINDOW=60000
RATE_LIMIT_MAX=100
```

### Security Headers

```typescript
// Security middleware
import helmet from 'helmet';

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", 'https://cdn.jsdelivr.net'],
      styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
      fontSrc: ["'self'", 'https://fonts.gstatic.com'],
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'", 'https://api.dinkhouse.com', 'wss://'],
    }
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
    preload: true
  }
}));
```

## Scaling Strategy

### Horizontal Scaling Configuration

```javascript
const scalingConfig = {
  frontend: {
    instances: 'auto', // Vercel handles automatically
    regions: ['iad1', 'sfo1'], // Multi-region deployment
    cdn: true
  },

  api: {
    minInstances: 2,
    maxInstances: 10,
    targetCPU: 70,
    targetMemory: 80
  },

  database: {
    readReplicas: 2,
    connectionPool: {
      min: 10,
      max: 100
    }
  },

  cache: {
    redis: {
      cluster: true,
      nodes: 3
    }
  }
};
```

## Backup & Disaster Recovery

### Backup Strategy

```bash
# Automated backup script
#!/bin/bash

# Database backup
pg_dump $DATABASE_URL > backup_$(date +%Y%m%d_%H%M%S).sql

# Upload to S3
aws s3 cp backup_*.sql s3://dinkhouse-backups/database/

# Application backup
tar -czf app_backup_$(date +%Y%m%d).tar.gz /app

# Retention policy (keep 30 days)
find /backups -name "*.sql" -mtime +30 -delete
```

### Disaster Recovery Plan

1. **RTO (Recovery Time Objective)**: 4 hours
2. **RPO (Recovery Point Objective)**: 1 hour
3. **Backup Frequency**: Every hour
4. **Backup Locations**: Multi-region S3
5. **Testing Schedule**: Monthly DR drills