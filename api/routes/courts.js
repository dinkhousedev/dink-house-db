const express = require('express');

const VALID_ENVIRONMENTS = ['indoor', 'outdoor'];

function parseDateParam(value, label) {
  if (!value) {
    return null;
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) {
    const error = new Error(`${label} must be a valid date/time`);
    error.status = 400;
    throw error;
  }

  return parsed;
}

function filterBookingsByRange(court, startDate, endDate) {
  if (!startDate && !endDate) {
    return court;
  }

  const clone = { ...court };

  if (Array.isArray(court.bookings)) {
    clone.bookings = court.bookings.filter((booking) => {
      const bookingStart = booking?.start_time ? new Date(booking.start_time) : null;
      const bookingEnd = booking?.end_time ? new Date(booking.end_time) : null;

      if (!bookingStart || !bookingEnd) {
        return true;
      }

      if (startDate && bookingEnd <= startDate) {
        return false;
      }

      if (endDate && bookingStart >= endDate) {
        return false;
      }

      return true;
    });
  }

  if (Array.isArray(court.availability_schedule)) {
    clone.availability_schedule = court.availability_schedule.filter((slot) => {
      const slotDate = slot?.date ? new Date(slot.date) : null;
      if (!slotDate) {
        return true;
      }

      if (startDate && slotDate < startDate) {
        return false;
      }

      if (endDate && slotDate > endDate) {
        return false;
      }

      return true;
    });
  }

  return clone;
}

async function getCourtsFromView(supabase) {
  const { data, error } = await supabase
    .schema('api')
    .from('court_availability_view')
    .select('*')
    .order('court_number', { ascending: true });

  if (error) {
    const err = new Error('Failed to load courts');
    err.status = 500;
    err.cause = error;
    throw err;
  }

  return data ?? [];
}

module.exports = (supabase) => {
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      const startDate = parseDateParam(req.query.start, 'start');
      const endDate = parseDateParam(req.query.end, 'end');
      const environment = req.query.environment;

      if (environment && !VALID_ENVIRONMENTS.includes(environment)) {
        return res.status(400).json({ error: `environment must be one of: ${VALID_ENVIRONMENTS.join(', ')}` });
      }

      const courts = await getCourtsFromView(supabase);

      const filtered = courts
        .filter((court) => {
          if (!environment) {
            return true;
          }
          return court.environment === environment;
        })
        .map((court) => filterBookingsByRange(court, startDate, endDate));

      return res.json({ courts: filtered });
    } catch (err) {
      const status = err.status ?? 500;
      if (err.cause) {
        console.error('Failed to list courts:', err.cause);
      } else {
        console.error('Unexpected error listing courts:', err);
      }
      return res.status(status).json({ error: err.message || 'Unexpected server error' });
    }
  });

  async function handleSingleCourtRequest(req, res) {
    try {
      const { id } = req.params;
      const startDate = parseDateParam(req.query.start, 'start');
      const endDate = parseDateParam(req.query.end, 'end');

      const { data, error } = await supabase
        .schema('api')
        .from('court_availability_view')
        .select('*')
        .eq('id', id)
        .limit(1)
        .maybeSingle();

      if (error) {
        console.error('Failed to fetch court:', error);
        return res.status(500).json({ error: 'Failed to fetch court' });
      }

      if (!data) {
        return res.status(404).json({ error: 'Court not found' });
      }

      const court = filterBookingsByRange(data, startDate, endDate);
      return res.json({ court });
    } catch (err) {
      const status = err.status ?? 500;
      console.error('Unexpected error fetching court:', err);
      return res.status(status).json({ error: err.message || 'Unexpected server error' });
    }
  }

  router.get('/:id', handleSingleCourtRequest);
  router.get('/:id/availability', handleSingleCourtRequest);

  return router;
};
