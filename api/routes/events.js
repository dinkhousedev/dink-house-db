const express = require('express');
const { z } = require('zod');

const EVENT_TYPES = [
  'event_scramble',
  'dupr_open_play',
  'dupr_tournament',
  'non_dupr_tournament',
  'league',
  'clinic',
  'private_lesson'
];

const eventTypeEnum = z.enum([
  'event_scramble',
  'dupr_open_play',
  'dupr_tournament',
  'non_dupr_tournament',
  'league',
  'clinic',
  'private_lesson'
]);

const isoStringSchema = z.string().refine((value) => {
  const date = new Date(value);
  return !Number.isNaN(date.valueOf());
}, { message: 'Invalid date/time value' });

const duprRangeSchema = z.object({
  label: z.string().min(1),
  minRating: z.coerce.number({ invalid_type_error: 'minRating must be numeric' }),
  maxRating: z.coerce.number({ invalid_type_error: 'maxRating must be numeric' }).optional(),
  openEnded: z.boolean().optional(),
  minInclusive: z.boolean().optional(),
  maxInclusive: z.boolean().optional()
});

const createEventSchema = z.object({
  title: z.string().min(1),
  eventType: eventTypeEnum,
  description: z.string().max(5000).optional(),
  templateId: z.string().uuid().optional().nullable(),
  startTime: isoStringSchema,
  endTime: isoStringSchema,
  courtIds: z.array(z.string().uuid()).min(1),
  maxCapacity: z.coerce.number().int().positive().optional(),
  minCapacity: z.coerce.number().int().nonnegative().optional(),
  skillLevels: z.array(z.string()).optional(),
  priceMember: z.coerce.number().nonnegative().optional(),
  priceGuest: z.coerce.number().nonnegative().optional(),
  memberOnly: z.boolean().optional(),
  equipmentProvided: z.boolean().optional(),
  specialInstructions: z.string().max(5000).optional(),
  duprBracketId: z.string().uuid().optional().nullable(),
  duprRange: duprRangeSchema.optional(),
  checkInTime: isoStringSchema.optional()
});

const registerSchema = z.object({
  playerName: z.string().max(200).optional(),
  playerEmail: z.string().email().optional(),
  playerPhone: z.string().max(50).optional(),
  skillLevel: z.string().optional(),
  duprRating: z.coerce.number().nonnegative().optional(),
  notes: z.string().max(2000).optional()
});

function buildDuprPayload(eventPayload, isDuprEvent) {
  if (!isDuprEvent) {
    return {
      p_dupr_bracket_id: null,
      p_dupr_range_label: null,
      p_dupr_min_rating: null,
      p_dupr_max_rating: null,
      p_dupr_open_ended: false,
      p_dupr_min_inclusive: true,
      p_dupr_max_inclusive: true
    };
  }

  const suppliedRange = eventPayload.duprRange;
  const bracketId = eventPayload.duprBracketId ?? null;

  if (!bracketId && !suppliedRange) {
    throw new Error('DUPR events must include either duprBracketId or duprRange details');
  }

  if (suppliedRange) {
    const openEnded = suppliedRange.openEnded ?? false;
    if (!openEnded && typeof suppliedRange.maxRating === 'undefined') {
      throw new Error('DUPR events with bounded ranges require maxRating');
    }

    return {
      p_dupr_bracket_id: bracketId,
      p_dupr_range_label: suppliedRange.label,
      p_dupr_min_rating: suppliedRange.minRating,
      p_dupr_max_rating: openEnded ? null : suppliedRange.maxRating ?? null,
      p_dupr_open_ended: openEnded,
      p_dupr_min_inclusive: suppliedRange.minInclusive ?? true,
      p_dupr_max_inclusive: openEnded ? true : suppliedRange.maxInclusive ?? true
    };
  }

  return {
    p_dupr_bracket_id: bracketId,
    p_dupr_range_label: null,
    p_dupr_min_rating: null,
    p_dupr_max_rating: null,
    p_dupr_open_ended: false,
    p_dupr_min_inclusive: true,
    p_dupr_max_inclusive: true
  };
}

module.exports = (supabase) => {
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      const { start, end, eventType } = req.query;
      let query = supabase.schema('api')
        .from('events_calendar_view')
        .select('*')
        .order('start_time', { ascending: true });

      if (start) {
        const parsed = new Date(start);
        if (Number.isNaN(parsed.valueOf())) {
          return res.status(400).json({ error: 'Invalid start date parameter' });
        }
        query = query.gte('start_time', parsed.toISOString());
      }

      if (end) {
        const parsed = new Date(end);
        if (Number.isNaN(parsed.valueOf())) {
          return res.status(400).json({ error: 'Invalid end date parameter' });
        }
        query = query.lte('end_time', parsed.toISOString());
      }

      if (eventType) {
        const types = Array.isArray(eventType) ? eventType : [eventType];
        const invalid = types.filter((value) => !EVENT_TYPES.includes(value));
        if (invalid.length > 0) {
          return res.status(400).json({ error: `Unsupported eventType value(s): ${invalid.join(', ')}` });
        }
        query = query.in('event_type', types);
      }

      const { data, error } = await query;
      if (error) {
        console.error('Failed to fetch events:', error);
        return res.status(500).json({ error: 'Failed to fetch events' });
      }

      return res.json({ events: data ?? [] });
    } catch (err) {
      console.error('Unexpected error fetching events:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  router.get('/meta/types', (_req, res) => {
    res.json({ eventTypes: EVENT_TYPES });
  });

  router.get('/meta/dupr-brackets', async (_req, res) => {
    try {
      const { data, error } = await supabase
        .schema('events')
        .from('dupr_brackets')
        .select('*')
        .order('min_rating', { ascending: true, nullsFirst: true })
        .order('max_rating', { ascending: true, nullsFirst: true });

      if (error) {
        console.error('Failed to load DUPR brackets:', error);
        return res.status(500).json({ error: 'Failed to load DUPR brackets' });
      }

      return res.json({ brackets: data ?? [] });
    } catch (err) {
      console.error('Unexpected error loading DUPR brackets:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  router.get('/:id', async (req, res) => {
    const { id } = req.params;

    try {
      const { data, error } = await supabase
        .schema('api')
        .from('events_calendar_view')
        .select('*')
        .eq('id', id)
        .limit(1)
        .maybeSingle();

      if (error) {
        console.error('Failed to fetch event:', error);
        return res.status(500).json({ error: 'Failed to fetch event' });
      }

      if (!data) {
        return res.status(404).json({ error: 'Event not found' });
      }

      return res.json({ event: data });
    } catch (err) {
      console.error('Unexpected error fetching event:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  router.post('/', async (req, res) => {
    const parseResult = createEventSchema.safeParse(req.body);

    if (!parseResult.success) {
      return res.status(400).json({
        error: 'Invalid event payload',
        details: parseResult.error.flatten()
      });
    }

    const payload = parseResult.data;
    const startTime = new Date(payload.startTime);
    const endTime = new Date(payload.endTime);

    if (startTime >= endTime) {
      return res.status(400).json({ error: 'endTime must be after startTime' });
    }

    const uniqueCourtIds = Array.from(new Set(payload.courtIds));
    const isDuprEvent = ['dupr_open_play', 'dupr_tournament'].includes(payload.eventType);

    let duprPayload;
    try {
      duprPayload = buildDuprPayload(payload, isDuprEvent);
    } catch (err) {
      return res.status(400).json({ error: err.message });
    }

    const rpcInput = {
      p_title: payload.title,
      p_event_type: payload.eventType,
      p_start_time: startTime.toISOString(),
      p_end_time: endTime.toISOString(),
      p_court_ids: uniqueCourtIds,
      p_description: payload.description ?? null,
      p_template_id: payload.templateId ?? null,
      p_max_capacity: payload.maxCapacity ?? 16,
      p_min_capacity: payload.minCapacity ?? 4,
      p_skill_levels: payload.skillLevels ?? null,
      p_price_member: payload.priceMember ?? 0,
      p_price_guest: payload.priceGuest ?? 0,
      p_member_only: payload.memberOnly ?? false,
      p_equipment_provided: payload.equipmentProvided ?? false,
      p_special_instructions: payload.specialInstructions ?? null,
      ...duprPayload
    };

    try {
      const { data, error } = await supabase.schema('api').rpc('create_event_with_courts', rpcInput);

      if (error) {
        const status = error.code === 'P0001' ? 400 : 500;
        console.error('Failed to create event:', error);
        return res.status(status).json({ error: error.message || 'Failed to create event' });
      }

      return res.status(201).json({ event: data });
    } catch (err) {
      console.error('Unexpected error creating event:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  router.post('/:id/register', async (req, res) => {
    const { id } = req.params;
    const parseResult = registerSchema.safeParse(req.body);

    if (!parseResult.success) {
      return res.status(400).json({
        error: 'Invalid registration payload',
        details: parseResult.error.flatten()
      });
    }

    const payload = parseResult.data;

    if (!payload.playerEmail) {
      return res.status(400).json({ error: 'playerEmail is required for registration' });
    }

    try {
      const { data, error } = await supabase.schema('api').rpc('register_for_event', {
        p_event_id: id,
        p_player_name: payload.playerName ?? null,
        p_player_email: payload.playerEmail,
        p_player_phone: payload.playerPhone ?? null,
        p_skill_level: payload.skillLevel ?? null,
        p_dupr_rating: payload.duprRating ?? null,
        p_notes: payload.notes ?? null
      });

      if (error) {
        const status = error.code === 'P0001' ? 400 : 500;
        console.error('Failed to register for event:', error);
        return res.status(status).json({ error: error.message || 'Failed to register for event' });
      }

      return res.status(201).json({ registration: data });
    } catch (err) {
      console.error('Unexpected error registering for event:', err);
      return res.status(500).json({ error: 'Unexpected server error' });
    }
  });

  return router;
};
