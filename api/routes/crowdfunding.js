const express = require('express');
const { z } = require('zod');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

const router = express.Router();

// ============================================================================
// VALIDATION SCHEMAS
// ============================================================================

const createBackerSchema = z.object({
  email: z.string().email(),
  firstName: z.string().min(1).max(100),
  lastInitial: z.string().length(1),
  phone: z.string().max(30).optional(),
  city: z.string().max(100).optional(),
  state: z.string().length(2).optional()
});

const createContributionSchema = z.object({
  campaignId: z.string().uuid(),
  tierId: z.string().uuid().optional(),
  amount: z.number().positive(),
  isPublic: z.boolean().default(true),
  showAmount: z.boolean().default(true),
  customMessage: z.string().max(500).optional()
});

// ============================================================================
// PUBLIC ROUTES - Campaign Information
// ============================================================================

/**
 * GET /api/crowdfunding/campaigns
 * Get all active campaigns with progress
 */
router.get('/campaigns', async (req, res) => {
  const { supabase } = req;

  try {
    const { data: campaigns, error } = await supabase
      .from('campaign_types')
      .select('*')
      .eq('is_active', true)
      .order('display_order');

    if (error) throw error;

    // Calculate progress percentage for each campaign
    const campaignsWithProgress = campaigns.map(campaign => ({
      ...campaign,
      percentage: campaign.goal_amount > 0
        ? Math.round((campaign.current_amount / campaign.goal_amount) * 100)
        : 0
    }));

    res.json({
      success: true,
      data: campaignsWithProgress
    });
  } catch (error) {
    console.error('Error fetching campaigns:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch campaigns'
    });
  }
});

/**
 * GET /api/crowdfunding/campaigns/:id
 * Get single campaign details with tiers
 */
router.get('/campaigns/:id', async (req, res) => {
  const { supabase } = req;
  const { id } = req.params;

  try {
    // Get campaign details
    const { data: campaign, error: campaignError } = await supabase
      .from('campaign_types')
      .select('*')
      .eq('id', id)
      .eq('is_active', true)
      .single();

    if (campaignError) throw campaignError;
    if (!campaign) {
      return res.status(404).json({
        success: false,
        error: 'Campaign not found'
      });
    }

    // Get available tiers
    const { data: tiers, error: tiersError } = await supabase
      .from('contribution_tiers')
      .select('*')
      .eq('campaign_type_id', id)
      .eq('is_active', true)
      .order('display_order');

    if (tiersError) throw tiersError;

    // Filter out full tiers and calculate spots remaining
    const availableTiers = tiers
      .filter(tier => !tier.max_backers || tier.current_backers < tier.max_backers)
      .map(tier => ({
        ...tier,
        spotsRemaining: tier.max_backers
          ? tier.max_backers - tier.current_backers
          : null
      }));

    res.json({
      success: true,
      data: {
        campaign: {
          ...campaign,
          percentage: campaign.goal_amount > 0
            ? Math.round((campaign.current_amount / campaign.goal_amount) * 100)
            : 0
        },
        tiers: availableTiers
      }
    });
  } catch (error) {
    console.error('Error fetching campaign:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch campaign details'
    });
  }
});

/**
 * GET /api/crowdfunding/founders-wall
 * Get public founders wall entries
 */
router.get('/founders-wall', async (req, res) => {
  const { supabase } = req;

  try {
    const { data: founders, error } = await supabase
      .from('founders_wall')
      .select('display_name, location, contribution_tier, total_contributed, is_featured')
      .order('total_contributed', { ascending: false })
      .order('display_order');

    if (error) throw error;

    res.json({
      success: true,
      data: founders
    });
  } catch (error) {
    console.error('Error fetching founders wall:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch founders wall'
    });
  }
});

/**
 * GET /api/crowdfunding/court-sponsors
 * Get active court sponsors
 */
router.get('/court-sponsors', async (req, res) => {
  const { supabase } = req;

  try {
    const { data: sponsors, error } = await supabase
      .from('court_sponsors')
      .select(`
        sponsor_name,
        sponsor_type,
        logo_url,
        court_number,
        sponsorship_start,
        sponsorship_end
      `)
      .eq('is_active', true)
      .order('display_order');

    if (error) throw error;

    res.json({
      success: true,
      data: sponsors
    });
  } catch (error) {
    console.error('Error fetching court sponsors:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch court sponsors'
    });
  }
});

// ============================================================================
// BACKER ROUTES
// ============================================================================

/**
 * GET /api/crowdfunding/backers/search
 * Search for a backer by email
 */
router.get('/backers/search', async (req, res) => {
  const { supabase } = req;
  const { email } = req.query;

  if (!email) {
    return res.status(400).json({
      success: false,
      error: 'Email parameter is required'
    });
  }

  try {
    const { data: backer, error } = await supabase
      .from('backers')
      .select('*')
      .eq('email', email.toLowerCase())
      .single();

    if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
      throw error;
    }

    res.json({
      success: true,
      data: backer
    });
  } catch (error) {
    console.error('Error searching for backer:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to search for backer'
    });
  }
});

// ============================================================================
// CONTRIBUTION ROUTES
// ============================================================================

/**
 * POST /api/crowdfunding/create-checkout-session
 * Create Stripe checkout session for contribution
 */
router.post('/create-checkout-session', async (req, res) => {
  const { supabase } = req;

  try {
    // Validate request body
    const validationResult = createBackerSchema.safeParse(req.body.backer);
    if (!validationResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid backer information',
        details: validationResult.error.errors
      });
    }

    const contributionResult = createContributionSchema.safeParse(req.body.contribution);
    if (!contributionResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid contribution information',
        details: contributionResult.error.errors
      });
    }

    const backerData = validationResult.data;
    const contributionData = contributionResult.data;

    // Get or create backer
    let backer;
    const { data: existingBacker } = await supabase
      .from('backers')
      .select('*')
      .eq('email', backerData.email)
      .single();

    if (existingBacker) {
      backer = existingBacker;
    } else {
      const { data: newBacker, error: backerError } = await supabase
        .from('backers')
        .insert([{
          email: backerData.email,
          first_name: backerData.firstName,
          last_initial: backerData.lastInitial,
          phone: backerData.phone,
          city: backerData.city,
          state: backerData.state
        }])
        .select()
        .single();

      if (backerError) throw backerError;
      backer = newBacker;
    }

    // Get campaign and tier details for Stripe metadata
    const { data: campaign } = await supabase
      .from('campaign_types')
      .select('name, slug')
      .eq('id', contributionData.campaignId)
      .single();

    let tierName = null;
    if (contributionData.tierId) {
      const { data: tier } = await supabase
        .from('contribution_tiers')
        .select('name')
        .eq('id', contributionData.tierId)
        .single();
      tierName = tier?.name;
    }

    // Create Stripe checkout session
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      line_items: [
        {
          price_data: {
            currency: 'usd',
            product_data: {
              name: tierName
                ? `${campaign.name} - ${tierName}`
                : campaign.name,
              description: contributionData.customMessage || 'Crowdfunding contribution'
            },
            unit_amount: Math.round(contributionData.amount * 100) // Convert to cents
          },
          quantity: 1
        }
      ],
      mode: 'payment',
      success_url: `${process.env.SITE_URL}/crowdfunding/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${process.env.SITE_URL}/crowdfunding?cancelled=true`,
      customer_email: backerData.email,
      metadata: {
        backer_id: backer.id,
        campaign_id: contributionData.campaignId,
        tier_id: contributionData.tierId || '',
        is_public: contributionData.isPublic.toString(),
        show_amount: contributionData.showAmount.toString(),
        custom_message: contributionData.customMessage || ''
      }
    });

    // Create pending contribution record
    const { error: contributionError } = await supabase
      .from('contributions')
      .insert([{
        backer_id: backer.id,
        campaign_type_id: contributionData.campaignId,
        tier_id: contributionData.tierId,
        amount: contributionData.amount,
        stripe_checkout_session_id: session.id,
        status: 'pending',
        is_public: contributionData.isPublic,
        show_amount: contributionData.showAmount,
        custom_message: contributionData.customMessage
      }]);

    if (contributionError) throw contributionError;

    res.json({
      success: true,
      data: {
        sessionId: session.id,
        url: session.url
      }
    });
  } catch (error) {
    console.error('Error creating checkout session:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create checkout session',
      message: error.message
    });
  }
});

/**
 * POST /api/crowdfunding/webhook
 * Handle Stripe webhook events
 */
router.post('/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  const sig = req.headers['stripe-signature'];
  const { supabase } = req;

  let event;

  try {
    event = stripe.webhooks.constructEvent(
      req.body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );
  } catch (err) {
    console.error('Webhook signature verification failed:', err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  // Handle the event
  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object;

        // Update contribution to completed
        const { error: updateError } = await supabase
          .from('contributions')
          .update({
            status: 'completed',
            stripe_payment_intent_id: session.payment_intent,
            completed_at: new Date().toISOString()
          })
          .eq('stripe_checkout_session_id', session.id);

        if (updateError) {
          console.error('Error updating contribution:', updateError);
        }

        // The database triggers will handle updating campaign totals,
        // backer totals, and founders wall entries
        break;
      }

      case 'charge.succeeded': {
        const charge = event.data.object;

        // Update contribution with charge ID
        const { error: chargeError } = await supabase
          .from('contributions')
          .update({
            stripe_charge_id: charge.id,
            payment_method: charge.payment_method_details?.type || 'card'
          })
          .eq('stripe_payment_intent_id', charge.payment_intent);

        if (chargeError) {
          console.error('Error updating charge:', chargeError);
        }
        break;
      }

      case 'charge.refunded': {
        const charge = event.data.object;

        // Update contribution to refunded
        const { error: refundError } = await supabase
          .from('contributions')
          .update({
            status: 'refunded',
            refunded_at: new Date().toISOString()
          })
          .eq('stripe_charge_id', charge.id);

        if (refundError) {
          console.error('Error updating refund:', refundError);
        }
        break;
      }

      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error) {
    console.error('Error handling webhook:', error);
    res.status(500).json({ error: 'Webhook handler failed' });
  }
});

/**
 * GET /api/crowdfunding/contribution/:sessionId
 * Get contribution details by checkout session ID (for success page)
 */
router.get('/contribution/:sessionId', async (req, res) => {
  const { supabase } = req;
  const { sessionId } = req.params;

  try {
    const { data: contribution, error } = await supabase
      .from('contributions')
      .select(`
        *,
        backer:backers(first_name, last_initial),
        campaign:campaign_types(name, slug),
        tier:contribution_tiers(name)
      `)
      .eq('stripe_checkout_session_id', sessionId)
      .single();

    if (error) throw error;

    if (!contribution) {
      return res.status(404).json({
        success: false,
        error: 'Contribution not found'
      });
    }

    res.json({
      success: true,
      data: contribution
    });
  } catch (error) {
    console.error('Error fetching contribution:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch contribution details'
    });
  }
});

// ============================================================================
// BENEFIT REDEMPTION & FULFILLMENT ROUTES (Admin/Staff)
// ============================================================================

/**
 * GET /api/crowdfunding/backer/:id/benefits
 * Get all benefits for a specific backer
 */
router.get('/backer/:id/benefits', async (req, res) => {
  const { supabase } = req;
  const { id } = req.params;

  try {
    const { data: benefits, error } = await supabase
      .from('v_active_backer_benefits')
      .select('*')
      .eq('backer_id', id);

    if (error) throw error;

    res.json({
      success: true,
      data: benefits
    });
  } catch (error) {
    console.error('Error fetching backer benefits:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch backer benefits'
    });
  }
});

/**
 * POST /api/crowdfunding/benefits/redeem
 * Log benefit usage/redemption
 */
router.post('/benefits/redeem', async (req, res) => {
  const { supabase } = req;
  const {
    allocationId,
    backerId,
    quantityUsed = 1,
    usedFor,
    notes,
    staffId,
    staffVerified = false
  } = req.body;

  try {
    // Validate allocation exists and has remaining quantity
    const { data: allocation, error: allocationError } = await supabase
      .from('benefit_allocations')
      .select('*')
      .eq('id', allocationId)
      .single();

    if (allocationError) throw allocationError;

    if (!allocation) {
      return res.status(404).json({
        success: false,
        error: 'Benefit allocation not found'
      });
    }

    if (allocation.remaining !== null && allocation.remaining < quantityUsed) {
      return res.status(400).json({
        success: false,
        error: `Insufficient quantity remaining. Available: ${allocation.remaining}, Requested: ${quantityUsed}`
      });
    }

    // Check if benefit is expired
    if (allocation.valid_until && new Date(allocation.valid_until) < new Date()) {
      return res.status(400).json({
        success: false,
        error: 'This benefit has expired'
      });
    }

    // Log the usage
    const { data: usageLog, error: logError } = await supabase
      .from('benefit_usage_log')
      .insert([{
        allocation_id: allocationId,
        backer_id: backerId,
        quantity_used: quantityUsed,
        used_for: usedFor,
        notes: notes,
        staff_verified: staffVerified,
        staff_id: staffId
      }])
      .select()
      .single();

    if (logError) throw logError;

    // Get updated allocation
    const { data: updatedAllocation } = await supabase
      .from('benefit_allocations')
      .select('*')
      .eq('id', allocationId)
      .single();

    res.json({
      success: true,
      data: {
        usageLog,
        updatedAllocation
      },
      message: 'Benefit redeemed successfully'
    });
  } catch (error) {
    console.error('Error redeeming benefit:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to redeem benefit',
      message: error.message
    });
  }
});

/**
 * GET /api/crowdfunding/benefits/usage-history/:allocationId
 * Get usage history for a specific benefit allocation
 */
router.get('/benefits/usage-history/:allocationId', async (req, res) => {
  const { supabase } = req;
  const { allocationId } = req.params;

  try {
    const { data: history, error } = await supabase
      .from('benefit_usage_log')
      .select('*')
      .eq('allocation_id', allocationId)
      .order('usage_time', { ascending: false });

    if (error) throw error;

    res.json({
      success: true,
      data: history
    });
  } catch (error) {
    console.error('Error fetching usage history:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch usage history'
    });
  }
});

/**
 * PATCH /api/crowdfunding/benefits/:id/fulfill
 * Mark a benefit as fulfilled (for non-consumable benefits)
 */
router.patch('/benefits/:id/fulfill', async (req, res) => {
  const { supabase } = req;
  const { id } = req.params;
  const { staffId, notes } = req.body;

  try {
    const { data: benefit, error } = await supabase
      .from('benefit_allocations')
      .update({
        fulfillment_status: 'fulfilled',
        fulfilled_by: staffId,
        fulfilled_at: new Date().toISOString(),
        fulfillment_notes: notes
      })
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;

    res.json({
      success: true,
      data: benefit,
      message: 'Benefit marked as fulfilled'
    });
  } catch (error) {
    console.error('Error fulfilling benefit:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fulfill benefit'
    });
  }
});

/**
 * PATCH /api/crowdfunding/benefits/:id/status
 * Update benefit fulfillment status
 */
router.patch('/benefits/:id/status', async (req, res) => {
  const { supabase } = req;
  const { id } = req.params;
  const { status, staffId, notes } = req.body;

  const validStatuses = ['allocated', 'in_progress', 'fulfilled', 'expired', 'cancelled'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({
      success: false,
      error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
    });
  }

  try {
    const updateData = {
      fulfillment_status: status,
      fulfillment_notes: notes
    };

    if (status === 'fulfilled') {
      updateData.fulfilled_by = staffId;
      updateData.fulfilled_at = new Date().toISOString();
    }

    const { data: benefit, error } = await supabase
      .from('benefit_allocations')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;

    res.json({
      success: true,
      data: benefit,
      message: `Benefit status updated to ${status}`
    });
  } catch (error) {
    console.error('Error updating benefit status:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update benefit status'
    });
  }
});

/**
 * GET /api/crowdfunding/benefits/pending
 * Get all pending benefits requiring fulfillment
 */
router.get('/benefits/pending', async (req, res) => {
  const { supabase } = req;
  const { benefitType } = req.query;

  try {
    let query = supabase
      .from('v_pending_fulfillment')
      .select('*')
      .order('days_until_expiration', { ascending: true, nullsLast: true });

    if (benefitType) {
      query = query.eq('benefit_type', benefitType);
    }

    const { data: benefits, error } = await query;

    if (error) throw error;

    res.json({
      success: true,
      data: benefits
    });
  } catch (error) {
    console.error('Error fetching pending benefits:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch pending benefits'
    });
  }
});

/**
 * GET /api/crowdfunding/benefits/summary
 * Get fulfillment summary statistics
 */
router.get('/benefits/summary', async (req, res) => {
  const { supabase } = req;

  try {
    const { data: summary, error } = await supabase
      .from('v_fulfillment_summary')
      .select('*')
      .order('benefit_type');

    if (error) throw error;

    res.json({
      success: true,
      data: summary
    });
  } catch (error) {
    console.error('Error fetching benefit summary:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch benefit summary'
    });
  }
});

// ============================================================================
// RECOGNITION ITEMS ROUTES (Admin/Staff)
// ============================================================================

/**
 * GET /api/crowdfunding/recognition-items
 * Get all recognition items with optional status filter
 */
router.get('/recognition-items', async (req, res) => {
  const { supabase } = req;
  const { status } = req.query;

  try {
    let query = supabase
      .from('recognition_items')
      .select(`
        *,
        backer:backers(email, first_name, last_initial, phone),
        allocation:benefit_allocations(benefit_name, tier_id)
      `)
      .order('created_at', { ascending: false });

    if (status) {
      query = query.eq('status', status);
    }

    const { data: items, error } = await query;

    if (error) throw error;

    res.json({
      success: true,
      data: items
    });
  } catch (error) {
    console.error('Error fetching recognition items:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch recognition items'
    });
  }
});

/**
 * GET /api/crowdfunding/recognition-items/pending
 * Get pending recognition items requiring action
 */
router.get('/recognition-items/pending', async (req, res) => {
  const { supabase } = req;

  try {
    const { data: items, error } = await supabase
      .from('v_pending_recognition_items')
      .select('*');

    if (error) throw error;

    res.json({
      success: true,
      data: items
    });
  } catch (error) {
    console.error('Error fetching pending recognition items:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch pending recognition items'
    });
  }
});

/**
 * PATCH /api/crowdfunding/recognition-items/:id
 * Update recognition item details and status
 */
router.patch('/recognition-items/:id', async (req, res) => {
  const { supabase } = req;
  const { id } = req.params;
  const updateData = req.body;

  try {
    const { data: item, error } = await supabase
      .from('recognition_items')
      .update({
        ...updateData,
        updated_at: new Date().toISOString()
      })
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;

    res.json({
      success: true,
      data: item,
      message: 'Recognition item updated successfully'
    });
  } catch (error) {
    console.error('Error updating recognition item:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update recognition item'
    });
  }
});

/**
 * PATCH /api/crowdfunding/recognition-items/:id/status
 * Update recognition item status workflow
 */
router.patch('/recognition-items/:id/status', async (req, res) => {
  const { supabase } = req;
  const { id } = req.params;
  const { status, staffId, notes } = req.body;

  const validStatuses = ['pending', 'ordered', 'in_production', 'received', 'installed', 'verified', 'cancelled'];
  if (!validStatuses.includes(status)) {
    return res.status(400).json({
      success: false,
      error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
    });
  }

  try {
    const updateData = {
      status,
      notes,
      updated_at: new Date().toISOString()
    };

    // Set date fields based on status
    const currentDate = new Date().toISOString().split('T')[0];
    switch (status) {
      case 'ordered':
        updateData.order_date = currentDate;
        updateData.ordered_by = staffId;
        break;
      case 'in_production':
        updateData.production_started = currentDate;
        break;
      case 'installed':
        updateData.installation_date = currentDate;
        updateData.installed_by = staffId;
        break;
      case 'verified':
        updateData.verified_at = new Date().toISOString();
        updateData.verified_by = staffId;
        break;
    }

    const { data: item, error } = await supabase
      .from('recognition_items')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;

    // If verified, also mark the benefit allocation as fulfilled
    if (status === 'verified') {
      await supabase
        .from('benefit_allocations')
        .update({
          fulfillment_status: 'fulfilled',
          fulfilled_by: staffId,
          fulfilled_at: new Date().toISOString()
        })
        .eq('id', item.allocation_id);
    }

    res.json({
      success: true,
      data: item,
      message: `Recognition item status updated to ${status}`
    });
  } catch (error) {
    console.error('Error updating recognition item status:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update recognition item status'
    });
  }
});

module.exports = router;
