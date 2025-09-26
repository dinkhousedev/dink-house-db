/**
 * Auth Webhook Edge Function
 * Handles authentication events from Supabase Auth
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { type, record, old_record } = await req.json();

    switch (type) {
      case 'INSERT':
        // New user registered
        await handleUserRegistration(supabase, record);
        break;

      case 'UPDATE':
        // User updated
        await handleUserUpdate(supabase, record, old_record);
        break;

      case 'DELETE':
        // User deleted
        await handleUserDeletion(supabase, old_record);
        break;
    }

    return new Response(
      JSON.stringify({ success: true }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

async function handleUserRegistration(supabase, user) {
  // Send welcome email
  const { error: emailError } = await supabase.functions.invoke('send-email', {
    body: {
      to: user.email,
      subject: 'Welcome to Dink House!',
      template: 'welcome',
      variables: {
        first_name: user.first_name,
        verification_token: user.verification_token,
      },
    },
  });

  if (emailError) {
    console.error('Failed to send welcome email:', emailError);
  }

  // Create default user preferences
  const { error: prefError } = await supabase
    .from('user_preferences')
    .insert({
      user_id: user.id,
      email_notifications: true,
      newsletter_subscription: true,
    });

  if (prefError) {
    console.error('Failed to create user preferences:', prefError);
  }

  // Log activity
  await supabase
    .from('system.activity_logs')
    .insert({
      user_id: user.id,
      action: 'user_registered',
      entity_type: 'user',
      entity_id: user.id,
      details: {
        email: user.email,
        username: user.username,
      },
    });
}

async function handleUserUpdate(supabase, newUser, oldUser) {
  // Check if email was verified
  if (!oldUser.is_verified && newUser.is_verified) {
    // Send confirmation email
    await supabase.functions.invoke('send-email', {
      body: {
        to: newUser.email,
        subject: 'Email Verified Successfully',
        template: 'email_verified',
        variables: {
          first_name: newUser.first_name,
        },
      },
    });

    // Check for referral campaigns
    const { data: subscriber } = await supabase
      .from('launch.launch_subscribers')
      .select('*')
      .eq('email', newUser.email)
      .single();

    if (subscriber && !subscriber.user_id) {
      // Link subscriber to user
      await supabase
        .from('launch.launch_subscribers')
        .update({ user_id: newUser.id })
        .eq('id', subscriber.id);
    }
  }

  // Check if password was reset
  if (oldUser.password_reset_token && !newUser.password_reset_token) {
    // Send password reset confirmation
    await supabase.functions.invoke('send-email', {
      body: {
        to: newUser.email,
        subject: 'Password Reset Successful',
        template: 'password_reset_success',
        variables: {
          first_name: newUser.first_name,
        },
      },
    });
  }

  // Log activity
  await supabase
    .from('system.activity_logs')
    .insert({
      user_id: newUser.id,
      action: 'user_updated',
      entity_type: 'user',
      entity_id: newUser.id,
      details: {
        changes: getChanges(oldUser, newUser),
      },
    });
}

async function handleUserDeletion(supabase, user) {
  // Clean up user data
  // Note: Most cleanup should be handled by CASCADE DELETE in the database

  // Send goodbye email
  await supabase.functions.invoke('send-email', {
    body: {
      to: user.email,
      subject: 'Account Deleted',
      template: 'account_deleted',
      variables: {
        first_name: user.first_name,
      },
    },
  });

  // Log activity (using service role since user is deleted)
  await supabase
    .from('system.activity_logs')
    .insert({
      action: 'user_deleted',
      entity_type: 'user',
      entity_id: user.id,
      details: {
        email: user.email,
        username: user.username,
      },
    });
}

function getChanges(oldRecord, newRecord) {
  const changes = {};
  const trackFields = ['email', 'username', 'first_name', 'last_name', 'role', 'is_active', 'is_verified'];

  for (const field of trackFields) {
    if (oldRecord[field] !== newRecord[field]) {
      changes[field] = {
        old: oldRecord[field],
        new: newRecord[field],
      };
    }
  }

  return changes;
}