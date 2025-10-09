/**
 * Launch Subscribers API Routes
 * Handles newsletter subscriber management
 */

const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const { z } = require('zod');
const {
  rateLimiters,
  handleValidationErrors,
  sanitizeRequestBody,
  blockBadIPs
} = require('../middleware/security');

// Initialize Supabase - Using Cloud Instance
const supabase = createClient(
  process.env.SUPABASE_URL || 'https://wchxzbuuwssrnaxshseu.supabase.co',
  process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY || ''
);

// Validation schema for subscriber
const subscriberSchema = z.object({
  email: z.string().email(),
  firstName: z.string().min(1).max(100).optional(),
  lastName: z.string().min(1).max(100).optional(),
  phone: z.string().max(30).optional(),
  company: z.string().max(255).optional(),
  source: z.string().max(100).optional().default('website'),
  sourceCampaign: z.string().max(255).optional(),
  interests: z.array(z.string()).optional(),
});

/**
 * GET /api/subscribers
 * Get all subscribers with pagination and filtering
 */
router.get('/',
  rateLimiters.api,
  async (req, res) => {
  try {
    // TODO: Add authentication check here for admin access

    const {
      page = 1,
      limit = 50,
      search = '',
      isActive = 'true',
      sortBy = 'created_at',
      sortOrder = 'desc'
    } = req.query;

    const offset = (parseInt(page) - 1) * parseInt(limit);

    let query = supabase
      .from('launch_subscribers')
      .select('id, email, first_name, last_name, phone, company, source, is_active, subscription_date, created_at, tags, engagement_score', { count: 'exact' });

    // Apply filters
    if (search) {
      query = query.or(`email.ilike.%${search}%,first_name.ilike.%${search}%,last_name.ilike.%${search}%`);
    }

    if (isActive !== 'all') {
      query = query.eq('is_active', isActive === 'true');
    }

    // Apply sorting
    query = query.order(sortBy, { ascending: sortOrder === 'asc' });

    // Apply pagination
    query = query.range(offset, offset + parseInt(limit) - 1);

    const { data, error, count } = await query;

    if (error) {
      console.error('Database error:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch subscribers',
      });
    }

    res.json({
      success: true,
      data,
      pagination: {
        total: count,
        page: parseInt(page),
        limit: parseInt(limit),
        totalPages: Math.ceil(count / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching subscribers:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch subscribers',
    });
  }
});

/**
 * GET /api/subscribers/count
 * Get subscriber count and statistics
 */
router.get('/count',
  rateLimiters.api,
  async (req, res) => {
  try {
    // TODO: Add authentication check here for admin access

    // Get total active subscribers
    const { count: activeCount, error: activeError } = await supabase
      .from('launch_subscribers')
      .select('*', { count: 'exact', head: true })
      .eq('is_active', true);

    if (activeError) {
      throw activeError;
    }

    // Get total inactive subscribers
    const { count: inactiveCount, error: inactiveError } = await supabase
      .from('launch_subscribers')
      .select('*', { count: 'exact', head: true })
      .eq('is_active', false);

    if (inactiveError) {
      throw inactiveError;
    }

    // Get new subscribers from last week
    const lastWeek = new Date();
    lastWeek.setDate(lastWeek.getDate() - 7);

    const { count: newThisWeek, error: weekError } = await supabase
      .from('launch_subscribers')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', lastWeek.toISOString());

    if (weekError) {
      throw weekError;
    }

    // Get new subscribers from previous week
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

    const { count: newLastWeek, error: lastWeekError } = await supabase
      .from('launch_subscribers')
      .select('*', { count: 'exact', head: true })
      .gte('created_at', twoWeeksAgo.toISOString())
      .lt('created_at', lastWeek.toISOString());

    if (lastWeekError) {
      throw lastWeekError;
    }

    // Calculate week-over-week growth
    const growthRate = newLastWeek > 0
      ? (((newThisWeek - newLastWeek) / newLastWeek) * 100).toFixed(1)
      : newThisWeek > 0 ? 100 : 0;

    res.json({
      success: true,
      data: {
        total: activeCount + inactiveCount,
        active: activeCount,
        inactive: inactiveCount,
        newThisWeek,
        newLastWeek,
        growthRate: `${growthRate > 0 ? '+' : ''}${growthRate}%`,
      }
    });
  } catch (error) {
    console.error('Error fetching subscriber count:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch subscriber count',
    });
  }
});

/**
 * GET /api/subscribers/:id
 * Get a specific subscriber by ID
 */
router.get('/:id',
  rateLimiters.api,
  async (req, res) => {
  try {
    // TODO: Add authentication check here for admin access

    const { data, error } = await supabase
      .from('launch.launch_subscribers')
      .select('*')
      .eq('id', req.params.id)
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(404).json({
          success: false,
          error: 'Subscriber not found',
        });
      }
      throw error;
    }

    res.json({
      success: true,
      data,
    });
  } catch (error) {
    console.error('Error fetching subscriber:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch subscriber',
    });
  }
});

/**
 * POST /api/subscribers
 * Create a new subscriber (for landing page newsletter signup)
 */
router.post('/',
  blockBadIPs,
  rateLimiters.contact, // Use contact rate limiter for public endpoint
  sanitizeRequestBody,
  handleValidationErrors,
  async (req, res) => {
  try {
    // Validate request body
    const validationResult = subscriberSchema.safeParse(req.body);
    if (!validationResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid subscriber data',
        details: validationResult.error.errors,
      });
    }

    const subscriberData = validationResult.data;

    // Check if email already exists
    const { data: existingSubscriber } = await supabase
      .from('launch.launch_subscribers')
      .select('id, is_active')
      .eq('email', subscriberData.email)
      .single();

    if (existingSubscriber) {
      if (existingSubscriber.is_active) {
        return res.status(409).json({
          success: false,
          error: 'Email already subscribed',
        });
      } else {
        // Reactivate inactive subscriber
        const { data, error } = await supabase
          .from('launch.launch_subscribers')
          .update({
            is_active: true,
            subscription_date: new Date().toISOString(),
            unsubscribed_at: null,
          })
          .eq('id', existingSubscriber.id)
          .select()
          .single();

        if (error) throw error;

        return res.json({
          success: true,
          message: 'Subscription reactivated successfully',
          data,
        });
      }
    }

    // Create new subscriber
    const { data, error } = await supabase
      .from('launch.launch_subscribers')
      .insert({
        email: subscriberData.email,
        first_name: subscriberData.firstName,
        last_name: subscriberData.lastName,
        phone: subscriberData.phone,
        company: subscriberData.company,
        source: subscriberData.source,
        source_campaign: subscriberData.sourceCampaign,
        interests: subscriberData.interests,
        referrer_url: req.get('referer'),
        is_active: true,
      })
      .select()
      .single();

    if (error) {
      console.error('Database error:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to create subscriber',
      });
    }

    res.status(201).json({
      success: true,
      message: 'Subscribed successfully',
      data,
    });
  } catch (error) {
    console.error('Error creating subscriber:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create subscriber',
    });
  }
});

/**
 * PATCH /api/subscribers/:id
 * Update subscriber status or information
 */
router.patch('/:id',
  rateLimiters.api,
  sanitizeRequestBody,
  async (req, res) => {
  try {
    // TODO: Add authentication check here for admin access

    const { isActive, firstName, lastName, phone, company, tags, notes } = req.body;

    const updateData = {};
    if (isActive !== undefined) {
      updateData.is_active = isActive;
      if (!isActive) {
        updateData.unsubscribed_at = new Date().toISOString();
      }
    }
    if (firstName !== undefined) updateData.first_name = firstName;
    if (lastName !== undefined) updateData.last_name = lastName;
    if (phone !== undefined) updateData.phone = phone;
    if (company !== undefined) updateData.company = company;
    if (tags !== undefined) updateData.tags = tags;

    const { data, error } = await supabase
      .from('launch.launch_subscribers')
      .update(updateData)
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(404).json({
          success: false,
          error: 'Subscriber not found',
        });
      }
      throw error;
    }

    res.json({
      success: true,
      data,
    });
  } catch (error) {
    console.error('Error updating subscriber:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update subscriber',
    });
  }
});

/**
 * DELETE /api/subscribers/:id
 * Unsubscribe a subscriber (soft delete)
 */
router.delete('/:id',
  rateLimiters.api,
  async (req, res) => {
  try {
    const { reason } = req.body;

    const { data, error } = await supabase
      .from('launch.launch_subscribers')
      .update({
        is_active: false,
        unsubscribed_at: new Date().toISOString(),
        unsubscribe_reason: reason || 'User requested',
      })
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(404).json({
          success: false,
          error: 'Subscriber not found',
        });
      }
      throw error;
    }

    res.json({
      success: true,
      message: 'Unsubscribed successfully',
      data,
    });
  } catch (error) {
    console.error('Error unsubscribing:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to unsubscribe',
    });
  }
});

module.exports = router;
