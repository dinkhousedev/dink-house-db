/**
 * Send Email Edge Function
 * Handles email sending with templates
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Email templates
const templates = {
  welcome: {
    subject: 'Welcome to Dink House!',
    html: `
      <h2>Welcome {{first_name}}!</h2>
      <p>Thank you for joining Dink House. We're excited to have you on board.</p>
      <p>Please verify your email by clicking the link below:</p>
      <a href="{{verify_url}}" style="display: inline-block; padding: 10px 20px; background-color: #4CAF50; color: white; text-decoration: none; border-radius: 5px;">Verify Email</a>
      <p>If you didn't create an account, please ignore this email.</p>
    `,
  },
  email_verified: {
    subject: 'Email Verified Successfully',
    html: `
      <h2>Email Verified!</h2>
      <p>Hi {{first_name}},</p>
      <p>Your email has been successfully verified. You can now access all features of your account.</p>
      <a href="{{login_url}}" style="display: inline-block; padding: 10px 20px; background-color: #4CAF50; color: white; text-decoration: none; border-radius: 5px;">Login to Your Account</a>
    `,
  },
  password_reset: {
    subject: 'Reset Your Password',
    html: `
      <h2>Password Reset Request</h2>
      <p>Hi {{first_name}},</p>
      <p>We received a request to reset your password. Click the link below to set a new password:</p>
      <a href="{{reset_url}}" style="display: inline-block; padding: 10px 20px; background-color: #FF9800; color: white; text-decoration: none; border-radius: 5px;">Reset Password</a>
      <p>This link will expire in 1 hour.</p>
      <p>If you didn't request this, please ignore this email.</p>
    `,
  },
  password_reset_success: {
    subject: 'Password Reset Successful',
    html: `
      <h2>Password Changed</h2>
      <p>Hi {{first_name}},</p>
      <p>Your password has been successfully reset. You can now log in with your new password.</p>
      <p>If you didn't make this change, please contact support immediately.</p>
    `,
  },
  subscription_confirmation: {
    subject: 'Confirm Your Subscription',
    html: `
      <h2>Confirm Your Subscription</h2>
      <p>Hi {{first_name}},</p>
      <p>Thank you for subscribing to {{campaign_name}}!</p>
      <p>Please confirm your subscription by clicking the link below:</p>
      <a href="{{confirm_url}}" style="display: inline-block; padding: 10px 20px; background-color: #4CAF50; color: white; text-decoration: none; border-radius: 5px;">Confirm Subscription</a>
      <p>If you didn't subscribe, please ignore this email.</p>
    `,
  },
  contact_form_notification: {
    subject: 'New Contact Form Submission',
    html: `
      <h2>New Contact Form Submission</h2>
      <p><strong>Form:</strong> {{form_name}}</p>
      <p><strong>From:</strong> {{name}} ({{email}})</p>
      <p><strong>Subject:</strong> {{subject}}</p>
      <p><strong>Message:</strong></p>
      <blockquote style="border-left: 3px solid #ddd; padding-left: 10px; margin-left: 0;">
        {{message}}
      </blockquote>
      <p><a href="{{admin_url}}" style="display: inline-block; padding: 10px 20px; background-color: #2196F3; color: white; text-decoration: none; border-radius: 5px;">View in Admin</a></p>
    `,
  },
  notification: {
    subject: '{{subject}}',
    html: `
      <h2>{{title}}</h2>
      <div>{{content}}</div>
      {{#if action_url}}
      <p><a href="{{action_url}}" style="display: inline-block; padding: 10px 20px; background-color: #4CAF50; color: white; text-decoration: none; border-radius: 5px;">{{action_text}}</a></p>
      {{/if}}
    `,
  },
};

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { to, subject, template, variables = {}, html, text } = await req.json();

    // Validate input
    if (!to) {
      throw new Error('Recipient email is required');
    }

    let emailHtml = html;
    let emailSubject = subject;

    // Use template if provided
    if (template && templates[template]) {
      const tmpl = templates[template];
      emailSubject = subject || replaceVariables(tmpl.subject, variables);
      emailHtml = replaceVariables(tmpl.html, variables);
    } else if (!html && !text) {
      throw new Error('Either template, html, or text content is required');
    }

    // Add base URL to variables for links
    variables.base_url = Deno.env.get('APP_URL') || 'http://localhost:3000';
    variables.verify_url = `${variables.base_url}/auth/verify?token=${variables.verification_token}`;
    variables.reset_url = `${variables.base_url}/auth/reset-password?token=${variables.reset_token}`;
    variables.confirm_url = `${variables.base_url}/subscribe/confirm?token=${variables.verification_token}`;
    variables.login_url = `${variables.base_url}/login`;
    variables.admin_url = `${variables.base_url}/admin/inquiries/${variables.inquiry_id}`;

    // Send email using your preferred email service
    const emailSent = await sendEmail({
      to,
      subject: emailSubject,
      html: emailHtml,
      text,
    });

    if (!emailSent) {
      throw new Error('Failed to send email');
    }

    // Log email sent
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    await supabase
      .from('system.activity_logs')
      .insert({
        action: 'email_sent',
        entity_type: 'email',
        details: {
          to,
          subject: emailSubject,
          template,
        },
      });

    return new Response(
      JSON.stringify({ success: true, message: 'Email sent successfully' }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );
  } catch (error) {
    console.error('Email error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    );
  }
});

function replaceVariables(template, variables) {
  let result = template;

  // Replace simple variables
  Object.keys(variables).forEach((key) => {
    const regex = new RegExp(`{{${key}}}`, 'g');
    result = result.replace(regex, variables[key] || '');
  });

  // Handle conditionals (simplified)
  result = result.replace(/{{#if (\w+)}}([\s\S]*?){{\/if}}/g, (match, varName, content) => {
    return variables[varName] ? content : '';
  });

  return result;
}

async function sendEmail({ to, subject, html, text }) {
  // Option 1: Use Resend
  if (Deno.env.get('RESEND_API_KEY')) {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: Deno.env.get('EMAIL_FROM') || 'noreply@dinkhouse.com',
        to,
        subject,
        html,
        text,
      }),
    });

    return response.ok;
  }

  // Option 2: Use SendGrid
  if (Deno.env.get('SENDGRID_API_KEY')) {
    const response = await fetch('https://api.sendgrid.com/v3/mail/send', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('SENDGRID_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        personalizations: [{ to: [{ email: to }] }],
        from: { email: Deno.env.get('EMAIL_FROM') || 'noreply@dinkhouse.com' },
        subject,
        content: [
          { type: 'text/html', value: html },
          { type: 'text/plain', value: text || stripHtml(html) },
        ],
      }),
    });

    return response.ok;
  }

  // Option 3: Use SMTP (requires additional setup)
  // For development, just log the email
  console.log('Email would be sent:', { to, subject });
  return true;
}

function stripHtml(html) {
  return html.replace(/<[^>]*>/g, '').trim();
}