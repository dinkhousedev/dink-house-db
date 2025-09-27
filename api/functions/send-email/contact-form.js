// Supabase Edge Function to send contact form emails via MailPit
// Deploy with: supabase functions deploy contact-form-email

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// MailPit configuration (adjust these based on your setup)
const MAILPIT_HOST = Deno.env.get('MAILPIT_HOST') || 'localhost'
const MAILPIT_SMTP_PORT = Deno.env.get('MAILPIT_SMTP_PORT') || '1025'
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@dinkhousepb.com'
const TO_EMAIL = Deno.env.get('CONTACT_EMAIL') || 'contact@dinkhousepb.com'

// CORS headers for browser requests
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse the request body
    const { firstName, lastName, email, message, phone, company, subject } = await req.json()

    // Validate required fields
    if (!firstName || !lastName || !email || !message) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Missing required fields'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    // Format the email content
    const emailSubject = subject
      ? `Contact Form: ${subject}`
      : 'New Contact Form Submission - The Dink House'

    const emailBody = formatEmailBody({
      firstName,
      lastName,
      email,
      message,
      phone,
      company,
      subject,
      timestamp: new Date().toISOString()
    })

    // Send email via MailPit SMTP (for local testing)
    // In production, you would use a service like SendGrid, AWS SES, or Resend
    const emailSent = await sendToMailPit({
      from: FROM_EMAIL,
      to: TO_EMAIL,
      replyTo: email,
      subject: emailSubject,
      html: emailBody,
      text: formatPlainTextEmail({ firstName, lastName, email, message, phone, company, subject })
    })

    if (!emailSent) {
      throw new Error('Failed to send email')
    }

    // Also send a confirmation email to the user
    const confirmationSent = await sendToMailPit({
      from: FROM_EMAIL,
      to: email,
      subject: 'Thank you for contacting The Dink House',
      html: formatConfirmationEmail(firstName),
      text: `Hi ${firstName},\n\nThank you for reaching out to The Dink House! We've received your message and will get back to you as soon as possible.\n\nBest regards,\nThe Dink House Team`
    })

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Contact form submitted successfully',
        emailSent: true,
        confirmationSent
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    console.error('Error processing contact form:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || 'Internal server error'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

// Function to send email via MailPit (for local development/testing)
async function sendToMailPit(emailData) {
  try {
    // MailPit API endpoint for sending emails
    const mailpitUrl = `http://${MAILPIT_HOST}:8025/api/v1/send`

    const response = await fetch(mailpitUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        From: {
          Email: emailData.from,
          Name: 'The Dink House'
        },
        To: [{
          Email: emailData.to,
          Name: emailData.to === TO_EMAIL ? 'The Dink House Team' : ''
        }],
        ReplyTo: emailData.replyTo ? [{
          Email: emailData.replyTo
        }] : undefined,
        Subject: emailData.subject,
        HTML: emailData.html,
        Text: emailData.text
      })
    })

    if (!response.ok) {
      console.error('MailPit response:', await response.text())
      return false
    }

    return true
  } catch (error) {
    console.error('Error sending to MailPit:', error)
    // In development, you might want to return true anyway to not block the form
    // In production, use a proper email service
    return false
  }
}

// Format HTML email body
function formatEmailBody(data) {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { width: 100px; height: 100px; margin: 0 auto 10px; }
        .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 8px 8px; }
        .field { margin-bottom: 20px; }
        .label { font-weight: bold; color: #666; margin-bottom: 5px; }
        .value { background: white; padding: 10px; border-radius: 4px; border: 1px solid #ddd; }
        .message { background: white; padding: 15px; border-radius: 4px; border: 1px solid #ddd; white-space: pre-wrap; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #999; font-size: 12px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h2 style="color: white; margin: 0;">New Contact Form Submission</h2>
          <p style="color: rgba(255,255,255,0.9); margin: 5px 0;">The Dink House</p>
        </div>
        <div class="content">
          <div class="field">
            <div class="label">Name:</div>
            <div class="value">${data.firstName} ${data.lastName}</div>
          </div>

          <div class="field">
            <div class="label">Email:</div>
            <div class="value"><a href="mailto:${data.email}">${data.email}</a></div>
          </div>

          ${data.phone ? `
          <div class="field">
            <div class="label">Phone:</div>
            <div class="value">${data.phone}</div>
          </div>
          ` : ''}

          ${data.company ? `
          <div class="field">
            <div class="label">Company:</div>
            <div class="value">${data.company}</div>
          </div>
          ` : ''}

          ${data.subject ? `
          <div class="field">
            <div class="label">Subject:</div>
            <div class="value">${data.subject}</div>
          </div>
          ` : ''}

          <div class="field">
            <div class="label">Message:</div>
            <div class="message">${escapeHtml(data.message)}</div>
          </div>

          <div class="footer">
            <p>Submitted on: ${new Date(data.timestamp).toLocaleString()}</p>
            <p>Source: Landing Page</p>
          </div>
        </div>
      </div>
    </body>
    </html>
  `
}

// Format plain text email
function formatPlainTextEmail(data) {
  return `
NEW CONTACT FORM SUBMISSION - THE DINK HOUSE
============================================

Name: ${data.firstName} ${data.lastName}
Email: ${data.email}
${data.phone ? `Phone: ${data.phone}\n` : ''}${data.company ? `Company: ${data.company}\n` : ''}${data.subject ? `Subject: ${data.subject}\n` : ''}

Message:
--------
${data.message}

========================================
Submitted: ${new Date().toLocaleString()}
Source: Landing Page
  `.trim()
}

// Format confirmation email for the user
function formatConfirmationEmail(firstName) {
  return `
    <!DOCTYPE html>
    <html>
    <head>
      <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 30px; text-align: center; border-radius: 8px; }
        .content { background: white; padding: 30px; margin-top: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .button { display: inline-block; background: #CDFE00; color: black; padding: 12px 30px; text-decoration: none; border-radius: 4px; font-weight: bold; margin-top: 20px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1 style="color: white; margin: 0;">Thank You!</h1>
        </div>
        <div class="content">
          <p>Hi ${firstName},</p>
          <p>Thank you for reaching out to The Dink House! We've received your message and appreciate you taking the time to contact us.</p>
          <p>Our team will review your message and get back to you as soon as possible, typically within 24-48 hours.</p>
          <p>In the meantime, feel free to explore our website or follow us on social media for the latest updates!</p>
          <p>Best regards,<br>The Dink House Team</p>
        </div>
      </div>
    </body>
    </html>
  `
}

// Helper function to escape HTML
function escapeHtml(text) {
  const map = {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;'
  }
  return text.replace(/[&<>"']/g, m => map[m])
}