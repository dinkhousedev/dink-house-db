/**
 * Security Middleware
 * Provides rate limiting, input sanitization, and security headers
 */

const rateLimit = require('express-rate-limit');
const helmet = require('helmet');
const { body, validationResult } = require('express-validator');

// Rate limiting configurations for different endpoints
const rateLimiters = {
  // Contact form rate limiting - stricter
  contact: rateLimit({
    windowMs: 60 * 1000, // 1 minute
    max: 5, // 5 requests per minute
    message: 'Too many contact form submissions. Please wait a minute and try again.',
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
      res.status(429).json({
        success: false,
        error: 'Too many requests',
        message: 'Please wait before submitting another contact form.',
        retryAfter: 60
      });
    }
  }),

  // General API rate limiting
  api: rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // 100 requests per 15 minutes
    message: 'Too many requests from this IP.',
    standardHeaders: true,
    legacyHeaders: false
  }),

  // Auth endpoints rate limiting
  auth: rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 10, // 10 attempts per 15 minutes
    message: 'Too many authentication attempts.',
    skipSuccessfulRequests: true // Don't count successful auth
  })
};

// Input validation rules for contact form
const contactFormValidation = [
  body('firstName')
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('First name is required and must be less than 100 characters')
    .matches(/^[a-zA-Z\s'-]+$/)
    .withMessage('First name contains invalid characters'),

  body('lastName')
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Last name is required and must be less than 100 characters')
    .matches(/^[a-zA-Z\s'-]+$/)
    .withMessage('Last name contains invalid characters'),

  body('email')
    .trim()
    .isEmail()
    .withMessage('Invalid email address')
    .normalizeEmail()
    .isLength({ max: 255 })
    .withMessage('Email must be less than 255 characters'),

  body('phone')
    .optional({ checkFalsy: true })
    .trim()
    .matches(/^[\d\s()+-]+$/)
    .withMessage('Invalid phone number format')
    .isLength({ max: 30 })
    .withMessage('Phone number must be less than 30 characters'),

  body('company')
    .optional({ checkFalsy: true })
    .trim()
    .isLength({ max: 255 })
    .withMessage('Company name must be less than 255 characters')
    .matches(/^[a-zA-Z0-9\s'&.,()-]+$/)
    .withMessage('Company name contains invalid characters'),

  body('subject')
    .optional({ checkFalsy: true })
    .trim()
    .isLength({ max: 255 })
    .withMessage('Subject must be less than 255 characters'),

  body('message')
    .trim()
    .isLength({ min: 10, max: 5000 })
    .withMessage('Message must be between 10 and 5000 characters')
];

// Validation error handler middleware
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      error: 'Validation error',
      details: errors.array().map(err => ({
        field: err.path,
        message: err.msg
      }))
    });
  }
  next();
};

// Security headers configuration
const securityHeaders = helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      mediaSrc: ["'self'"],
      frameSrc: ["'none'"]
    }
  },
  crossOriginEmbedderPolicy: false
});

// CORS configuration for production
const corsOptions = {
  origin: function (origin, callback) {
    const allowedOrigins = [
      'https://dinkhousepb.com',
      'https://www.dinkhousepb.com',
      'https://admin.dinkhousepb.com',
      'http://localhost:3000',
      'http://localhost:3001'
    ];

    // Allow requests with no origin (mobile apps, Postman, etc.)
    if (!origin) return callback(null, true);

    if (allowedOrigins.indexOf(origin) !== -1) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true,
  optionsSuccessStatus: 200
};

// Sanitize user input to prevent XSS
const sanitizeInput = (input) => {
  if (typeof input !== 'string') return input;

  // Remove any HTML tags and script content
  return input
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
    .replace(/<[^>]+>/g, '')
    .trim();
};

// Middleware to sanitize all request body fields
const sanitizeRequestBody = (req, res, next) => {
  if (req.body) {
    Object.keys(req.body).forEach(key => {
      if (typeof req.body[key] === 'string') {
        req.body[key] = sanitizeInput(req.body[key]);
      }
    });
  }
  next();
};

// IP blocking middleware for known bad actors
const ipBlocklist = new Set();

const blockBadIPs = (req, res, next) => {
  const clientIp = req.ip || req.connection.remoteAddress;

  if (ipBlocklist.has(clientIp)) {
    return res.status(403).json({
      success: false,
      error: 'Access denied'
    });
  }

  next();
};

// Add IP to blocklist
const blockIP = (ip) => {
  ipBlocklist.add(ip);
  // Optionally, persist to database
};

// Remove IP from blocklist
const unblockIP = (ip) => {
  ipBlocklist.delete(ip);
};

module.exports = {
  rateLimiters,
  contactFormValidation,
  handleValidationErrors,
  securityHeaders,
  corsOptions,
  sanitizeInput,
  sanitizeRequestBody,
  blockBadIPs,
  blockIP,
  unblockIP
};