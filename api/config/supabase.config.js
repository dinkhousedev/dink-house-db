/**
 * Supabase Configuration
 * Central configuration for all Supabase services
 */

const config = {
  // Supabase Connection
  supabase: {
    url: process.env.SUPABASE_URL || 'http://localhost:9002',
    anonKey: process.env.SUPABASE_ANON_KEY || process.env.ANON_KEY,
    serviceKey: process.env.SUPABASE_SERVICE_KEY || process.env.SERVICE_KEY,
  },

  // Database Connection
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: process.env.DB_PORT || 9432,
    database: process.env.POSTGRES_DB || 'dink_house',
    user: process.env.POSTGRES_USER || 'postgres',
    password: process.env.POSTGRES_PASSWORD || 'DevPassword123!',
  },

  // JWT Configuration
  jwt: {
    secret: process.env.JWT_SECRET || 'your-super-secret-jwt-key-change-in-production',
    expiresIn: process.env.JWT_EXPIRY || 3600,
    algorithm: 'HS256',
  },

  // API Settings
  api: {
    version: 'v1',
    rateLimit: process.env.API_RATE_LIMIT || 100,
    corsOrigins: (process.env.API_CORS_ORIGINS || 'http://localhost:3000,http://localhost:3001').split(','),
    maxRequestSize: '10mb',
  },

  // Storage Configuration
  storage: {
    buckets: {
      media: 'media-files',
      documents: 'documents',
      avatars: 'user-avatars',
    },
    maxFileSize: process.env.MAX_FILE_SIZE || 10485760, // 10MB
    allowedMimeTypes: {
      images: ['image/jpeg', 'image/png', 'image/gif', 'image/webp'],
      documents: ['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
      videos: ['video/mp4', 'video/webm'],
    },
  },

  // Realtime Configuration
  realtime: {
    enabled: true,
    channels: {
      system: 'system-notifications',
      content: 'content-updates',
      contact: 'contact-submissions',
      launch: 'launch-campaigns',
    },
  },

  // Email Configuration
  email: {
    enabled: process.env.SMTP_HOST ? true : false,
    smtp: {
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: process.env.SMTP_PORT || 587,
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    },
    from: process.env.EMAIL_FROM || 'noreply@dinkhouse.com',
    templates: {
      verification: 'email-verification',
      passwordReset: 'password-reset',
      welcome: 'welcome',
      notification: 'notification',
    },
  },

  // Feature Flags
  features: {
    registration: true,
    socialAuth: false,
    twoFactorAuth: false,
    fileUploads: true,
    emailNotifications: true,
    realtimeUpdates: true,
  },

  // Security Settings
  security: {
    bcryptRounds: 10,
    maxLoginAttempts: 5,
    lockoutDuration: 15 * 60 * 1000, // 15 minutes
    sessionDuration: 24 * 60 * 60 * 1000, // 24 hours
    refreshTokenDuration: 7 * 24 * 60 * 60 * 1000, // 7 days
  },
};

module.exports = config;