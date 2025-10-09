const express = require('express');
const { z } = require('zod');

// Validation schemas
const registerSchema = z.object({
  instanceId: z.string().uuid(),
  playerId: z.string().uuid(),
  skillLevelLabel: z.string().min(1).max(100),
  notes: z.string().max(2000).optional(),
  paymentIntentId: z.string().optional() // Required for guests
});

const cancelRegistrationSchema = z.object({
  reason: z.string().max(1000).optional(),
  issueRefund: z.boolean().optional().default(false)
});

const historySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional().default(20),
  offset: z.coerce.number().int().min(0).optional().default(0)
});

const scheduleSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  daysAhead: z.coerce.number().int().min(1).max(90).optional().default(7)
});

module.exports = (supabase) => {
  const router = express.Router();

  /**
   * GET /api/open-play/schedule
   * Get upcoming open play schedule with availability
   */
  router.get('/schedule', async (req, res) => {
    try {
      const parseResult = scheduleSchema.safeParse(req.query);

      if (!parseResult.success) {
        return res.status(400).json({
          error: 'Invalid request parameters',
          details: parseResult.error.flatten()
        });
      }

      const { startDate, endDate, daysAhead } = parseResult.data;

      const { data, error } = await supabase
        .schema('api')
        .rpc('get_upcoming_open_play_schedule', {
          p_start_date: startDate || null,
          p_end_date: endDate || null,
          p_days_ahead: daysAhead
        });

      if (error) {
        console.error('Failed to fetch open play schedule:', error);
        return res.status(500).json({ error: 'Failed to fetch schedule' });
      }

      return res.json(data || { sessions: [] });
    } catch (err) {
      console.error('Unexpected error fetching open play schedule:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  /**
   * POST /api/open-play/register
   * Register/check-in a player for an open play session
   */
  router.post('/register', async (req, res) => {
    try {
      const parseResult = registerSchema.safeParse(req.body);

      if (!parseResult.success) {
        return res.status(400).json({
          error: 'Invalid registration payload',
          details: parseResult.error.flatten()
        });
      }

      const { instanceId, playerId, skillLevelLabel, notes, paymentIntentId } = parseResult.data;

      const { data, error } = await supabase
        .schema('api')
        .rpc('register_for_open_play', {
          p_instance_id: instanceId,
          p_player_id: playerId,
          p_skill_level_label: skillLevelLabel,
          p_notes: notes || null,
          p_payment_intent_id: paymentIntentId || null
        });

      if (error) {
        const status = error.code === 'P0001' ? 400 : 500;
        console.error('Failed to register for open play:', error);
        return res.status(status).json({
          error: error.message || 'Failed to register for open play'
        });
      }

      return res.status(201).json(data);
    } catch (err) {
      console.error('Unexpected error registering for open play:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  /**
   * GET /api/open-play/:instanceId/registrations
   * Get all registrations for a specific open play instance
   */
  router.get('/:instanceId/registrations', async (req, res) => {
    try {
      const { instanceId } = req.params;
      const includeCancelled = req.query.includeCancelled === 'true';

      // Validate UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(instanceId)) {
        return res.status(400).json({ error: 'Invalid instance ID format' });
      }

      const { data, error } = await supabase
        .schema('api')
        .rpc('get_open_play_registrations', {
          p_instance_id: instanceId,
          p_include_cancelled: includeCancelled
        });

      if (error) {
        console.error('Failed to fetch registrations:', error);
        return res.status(500).json({ error: 'Failed to fetch registrations' });
      }

      return res.json(data || { registrations: [] });
    } catch (err) {
      console.error('Unexpected error fetching registrations:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  /**
   * DELETE /api/open-play/registrations/:registrationId
   * Cancel an open play registration
   */
  router.delete('/registrations/:registrationId', async (req, res) => {
    try {
      const { registrationId } = req.params;

      // Validate UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(registrationId)) {
        return res.status(400).json({ error: 'Invalid registration ID format' });
      }

      const parseResult = cancelRegistrationSchema.safeParse(req.body);

      if (!parseResult.success) {
        return res.status(400).json({
          error: 'Invalid cancellation payload',
          details: parseResult.error.flatten()
        });
      }

      const { reason, issueRefund } = parseResult.data;

      const { data, error } = await supabase
        .schema('api')
        .rpc('cancel_open_play_registration', {
          p_registration_id: registrationId,
          p_reason: reason || null,
          p_issue_refund: issueRefund
        });

      if (error) {
        const status = error.code === 'P0001' ? 400 : 500;
        console.error('Failed to cancel registration:', error);
        return res.status(status).json({
          error: error.message || 'Failed to cancel registration'
        });
      }

      return res.json(data);
    } catch (err) {
      console.error('Unexpected error cancelling registration:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  /**
   * GET /api/open-play/player/:playerId/history
   * Get a player's open play session history
   */
  router.get('/player/:playerId/history', async (req, res) => {
    try {
      const { playerId } = req.params;

      // Validate UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(playerId)) {
        return res.status(400).json({ error: 'Invalid player ID format' });
      }

      const parseResult = historySchema.safeParse(req.query);

      if (!parseResult.success) {
        return res.status(400).json({
          error: 'Invalid query parameters',
          details: parseResult.error.flatten()
        });
      }

      const { limit, offset } = parseResult.data;

      const { data, error } = await supabase
        .schema('api')
        .rpc('get_player_open_play_history', {
          p_player_id: playerId,
          p_limit: limit,
          p_offset: offset
        });

      if (error) {
        console.error('Failed to fetch player history:', error);
        return res.status(500).json({ error: 'Failed to fetch player history' });
      }

      return res.json(data || { sessions: [] });
    } catch (err) {
      console.error('Unexpected error fetching player history:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  /**
   * GET /api/open-play/capacity/:instanceId/:skillLevel
   * Get current capacity for a specific skill level in an instance
   */
  router.get('/capacity/:instanceId/:skillLevel', async (req, res) => {
    try {
      const { instanceId, skillLevel } = req.params;

      // Validate UUID format
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(instanceId)) {
        return res.status(400).json({ error: 'Invalid instance ID format' });
      }

      const { data, error } = await supabase
        .schema('events')
        .rpc('get_skill_level_capacity', {
          p_instance_id: instanceId,
          p_skill_level_label: skillLevel
        });

      if (error) {
        console.error('Failed to fetch capacity:', error);
        return res.status(500).json({ error: 'Failed to fetch capacity' });
      }

      // Return first row if available
      const capacity = data && data.length > 0 ? data[0] : null;

      if (!capacity) {
        return res.status(404).json({
          error: 'Skill level not found for this instance'
        });
      }

      return res.json(capacity);
    } catch (err) {
      console.error('Unexpected error fetching capacity:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  /**
   * GET /api/open-play/fee/:playerId/:scheduleBlockId
   * Calculate the fee for a player for a specific schedule block
   */
  router.get('/fee/:playerId/:scheduleBlockId', async (req, res) => {
    try {
      const { playerId, scheduleBlockId } = req.params;

      // Validate UUID formats
      const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      if (!uuidRegex.test(playerId) || !uuidRegex.test(scheduleBlockId)) {
        return res.status(400).json({ error: 'Invalid ID format' });
      }

      const { data, error } = await supabase
        .schema('events')
        .rpc('calculate_open_play_fee', {
          p_player_id: playerId,
          p_schedule_block_id: scheduleBlockId
        });

      if (error) {
        console.error('Failed to calculate fee:', error);
        return res.status(500).json({ error: 'Failed to calculate fee' });
      }

      // Return first row if available
      const fee = data && data.length > 0 ? data[0] : null;

      if (!fee) {
        return res.status(404).json({
          error: 'Unable to calculate fee'
        });
      }

      return res.json(fee);
    } catch (err) {
      console.error('Unexpected error calculating fee:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  return router;
};
