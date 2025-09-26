/**
 * Supabase Client Library
 * Initialize and export Supabase client instances
 */

const { createClient } = require('@supabase/supabase-js');
const config = require('../config/supabase.config');

/**
 * Create anonymous client for public operations
 */
const supabaseAnon = createClient(
  config.supabase.url,
  config.supabase.anonKey,
  {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: true,
    },
    global: {
      headers: {
        'X-Client-Info': 'dink-house-api',
      },
    },
  }
);

/**
 * Create service client for admin operations
 */
const supabaseService = createClient(
  config.supabase.url,
  config.supabase.serviceKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: {
        'X-Client-Info': 'dink-house-service',
      },
    },
  }
);

/**
 * Helper function to create a client with custom JWT
 */
function createCustomClient(jwt) {
  return createClient(
    config.supabase.url,
    config.supabase.anonKey,
    {
      global: {
        headers: {
          Authorization: `Bearer ${jwt}`,
        },
      },
    }
  );
}

/**
 * Database query helper with error handling
 */
async function query(sql, params = [], useService = false) {
  const client = useService ? supabaseService : supabaseAnon;

  try {
    const { data, error } = await client.rpc('execute_sql', {
      query: sql,
      params: params,
    });

    if (error) throw error;
    return data;
  } catch (error) {
    console.error('Database query error:', error);
    throw error;
  }
}

/**
 * Transaction helper
 */
async function transaction(callback) {
  const client = supabaseService;

  try {
    await client.rpc('begin_transaction');
    const result = await callback(client);
    await client.rpc('commit_transaction');
    return result;
  } catch (error) {
    await client.rpc('rollback_transaction');
    throw error;
  }
}

/**
 * Batch insert helper
 */
async function batchInsert(table, records, options = {}) {
  const client = options.useService ? supabaseService : supabaseAnon;
  const batchSize = options.batchSize || 1000;
  const results = [];

  for (let i = 0; i < records.length; i += batchSize) {
    const batch = records.slice(i, i + batchSize);
    const { data, error } = await client
      .from(table)
      .insert(batch)
      .select();

    if (error) throw error;
    results.push(...data);
  }

  return results;
}

/**
 * Pagination helper
 */
async function paginate(table, options = {}) {
  const client = options.useService ? supabaseService : supabaseAnon;
  const page = options.page || 1;
  const perPage = options.perPage || 20;
  const offset = (page - 1) * perPage;

  let query = client.from(table).select('*', { count: 'exact' });

  if (options.filters) {
    Object.entries(options.filters).forEach(([key, value]) => {
      query = query.eq(key, value);
    });
  }

  if (options.orderBy) {
    query = query.order(options.orderBy, { ascending: options.ascending ?? true });
  }

  query = query.range(offset, offset + perPage - 1);

  const { data, count, error } = await query;

  if (error) throw error;

  return {
    data,
    pagination: {
      page,
      perPage,
      total: count,
      totalPages: Math.ceil(count / perPage),
    },
  };
}

/**
 * File upload helper
 */
async function uploadFile(bucket, path, file, options = {}) {
  const client = options.useService ? supabaseService : supabaseAnon;

  const { data, error } = await client.storage
    .from(bucket)
    .upload(path, file, {
      cacheControl: options.cacheControl || '3600',
      upsert: options.upsert || false,
      contentType: options.contentType,
    });

  if (error) throw error;

  // Get public URL
  const { data: { publicUrl } } = client.storage
    .from(bucket)
    .getPublicUrl(path);

  return {
    path: data.path,
    publicUrl,
  };
}

/**
 * Realtime subscription helper
 */
function subscribe(channel, callback, options = {}) {
  const client = options.useService ? supabaseService : supabaseAnon;

  const subscription = client
    .channel(channel)
    .on(
      options.event || '*',
      options.filter || {},
      callback
    )
    .subscribe();

  return subscription;
}

/**
 * Error handler wrapper
 */
function handleError(error) {
  console.error('Supabase error:', error);

  if (error.code === 'PGRST301') {
    return {
      status: 401,
      message: 'Authentication required',
    };
  }

  if (error.code === 'PGRST204') {
    return {
      status: 403,
      message: 'Insufficient permissions',
    };
  }

  if (error.code === '23505') {
    return {
      status: 409,
      message: 'Duplicate entry',
    };
  }

  return {
    status: 500,
    message: error.message || 'Internal server error',
  };
}

module.exports = {
  supabaseAnon,
  supabaseService,
  createCustomClient,
  query,
  transaction,
  batchInsert,
  paginate,
  uploadFile,
  subscribe,
  handleError,
  config,
};