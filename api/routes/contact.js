/**
 * Contact Form API Routes
 * Handles contact form submissions and email notifications
 */

const express = require('express');
const router = express.Router();
const { createClient } = require('@supabase/supabase-js');
const sgMail = require('@sendgrid/mail');
const { z } = require('zod');
const {
  rateLimiters,
  contactFormValidation,
  handleValidationErrors,
  sanitizeRequestBody,
  blockBadIPs
} = require('../middleware/security');

// Initialize SendGrid
sgMail.setApiKey(process.env.SENDGRID_API_KEY || '');

// Initialize Supabase - Using Cloud Instance
const supabase = createClient(
  process.env.SUPABASE_URL || 'https://wchxzbuuwssrnaxshseu.supabase.co',
  process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY || ''
);

// Validation schema for contact form
const contactFormSchema = z.object({
  firstName: z.string().min(1).max(100),
  lastName: z.string().min(1).max(100),
  email: z.string().email(),
  phone: z.string().optional(),
  company: z.string().optional(),
  subject: z.string().optional(),
  message: z.string().min(1).max(5000),
  formType: z.string().optional().default('contact'),
});

/**
 * POST /api/contact
 * Submit a contact form with enhanced security
 */
router.post('/',
  blockBadIPs,                    // Check IP blocklist
  rateLimiters.contact,           // Apply rate limiting
  sanitizeRequestBody,            // Sanitize input
  contactFormValidation,          // Validate input
  handleValidationErrors,         // Handle validation errors
  async (req, res) => {
  try {
    // Validate request body
    const validationResult = contactFormSchema.safeParse(req.body);
    if (!validationResult.success) {
      return res.status(400).json({
        success: false,
        error: 'Invalid form data',
        details: validationResult.error.errors,
      });
    }

    const formData = validationResult.data;

    // Store submission in database with sanitized data
    const { data: submission, error: dbError } = await supabase
      .from('contact.contact_inquiries')  // Using the correct table
      .insert({
        first_name: formData.firstName,
        last_name: formData.lastName,
        email: formData.email,
        phone: formData.phone,
        company: formData.company,
        subject: formData.subject,
        message: formData.message,
        source: 'website',
        ip_address: req.ip || req.connection.remoteAddress,
        user_agent: req.get('user-agent'),
        source_details: {
          referrer: req.get('referer'),
          timestamp: new Date().toISOString(),
          form_type: formData.formType
        },
      })
      .select()
      .single();

    if (dbError) {
      console.error('Database error:', dbError);
      return res.status(500).json({
        success: false,
        error: 'Failed to store submission',
      });
    }

    // Get email templates
    const { data: templates } = await supabase
      .from('system.email_templates')
      .select('*')
      .in('template_key', ['contact_form_thank_you', 'contact_form_admin'])
      .eq('is_active', true);

    const thankYouTemplate = templates?.find(t => t.template_key === 'contact_form_thank_you');
    const adminTemplate = templates?.find(t => t.template_key === 'contact_form_admin');

    // Prepare variables - using Supabase Cloud storage
    const logoUrl = process.env.LOGO_URL || 'https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg';
    const siteUrl = process.env.SITE_URL || 'https://dinkhousepb.com';

    const customerVariables = {
      first_name: formData.firstName,
      site_url: siteUrl,
      logo_url: logoUrl,
    };

    const adminVariables = {
      first_name: formData.firstName,
      last_name: formData.lastName,
      email: formData.email,
      phone: formData.phone || 'Not provided',
      company: formData.company || 'Not provided',
      subject: formData.subject || 'Not provided',
      message: formData.message,
      form_type: formData.formType,
      submission_id: submission.id,
      submitted_at: new Date().toLocaleString(),
      admin_url: `${siteUrl}/admin/contact/${submission.id}`,
    };

    // Send emails
    const emailPromises = [];

    // Customer thank you email
    if (thankYouTemplate) {
      emailPromises.push(
        sendEmail({
          to: formData.email,
          subject: replaceVariables(thankYouTemplate.subject, customerVariables),
          html: replaceVariables(thankYouTemplate.html_body, customerVariables),
          text: replaceVariables(thankYouTemplate.text_body || '', customerVariables),
        })
      );
    }

    // Admin notification email
    if (adminTemplate) {
      const adminEmail = process.env.ADMIN_EMAIL || 'admin@dinkhousepb.com';
      emailPromises.push(
        sendEmail({
          to: adminEmail,
          subject: replaceVariables(adminTemplate.subject, adminVariables),
          html: replaceVariables(adminTemplate.html_body, adminVariables),
          text: replaceVariables(adminTemplate.text_body || '', adminVariables),
          replyTo: formData.email,
        })
      );
    }

    // Send all emails
    const emailResults = await Promise.allSettled(emailPromises);

    // Log email results
    for (let i = 0; i < emailResults.length; i++) {
      const result = emailResults[i];
      const isCustomerEmail = i === 0;
      const templateKey = isCustomerEmail ? 'contact_form_thank_you' : 'contact_form_admin';
      const toEmail = isCustomerEmail ? formData.email : (process.env.ADMIN_EMAIL || 'admin@dinkhousepb.com');

      await supabase.rpc('log_email', {
        p_template_key: templateKey,
        p_to_email: toEmail,
        p_from_email: process.env.EMAIL_FROM || 'hello@dinkhousepb.com',
        p_subject: isCustomerEmail ? thankYouTemplate?.subject : adminTemplate?.subject,
        p_status: result.status === 'fulfilled' ? 'sent' : 'failed',
        p_metadata: {
          submission_id: submission.id,
          error: result.status === 'rejected' ? result.reason?.message : null,
        },
      });
    }

    res.json({
      success: true,
      message: 'Contact form submitted successfully',
      submissionId: submission.id,
    });
  } catch (error) {
    console.error('Contact form error:', error);
    res.status(500).json({
      success: false,
      error: 'An error occurred while processing your request',
    });
  }
});

/**
 * GET /api/contact/submissions
 * Get all contact form submissions (admin only)
 */
router.get('/submissions',
  rateLimiters.api,  // Apply general API rate limiting
  async (req, res) => {
  try {
    // TODO: Add authentication check here

    const { data, error } = await supabase
      .from('contact.contact_inquiries')  // Using the correct table
      .select('*')
      .order('created_at', { ascending: false });

    if (error) {
      throw error;
    }

    res.json({
      success: true,
      data,
    });
  } catch (error) {
    console.error('Error fetching submissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch submissions',
    });
  }
});

/**
 * GET /api/contact/submissions/:id
 * Get a specific contact form submission
 */
router.get('/submissions/:id',
  rateLimiters.api,  // Apply general API rate limiting
  async (req, res) => {
  try {
    // TODO: Add authentication check here

    const { data, error } = await supabase
      .from('contact.contact_inquiries')  // Using the correct table
      .select('*')
      .eq('id', req.params.id)
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(404).json({
          success: false,
          error: 'Submission not found',
        });
      }
      throw error;
    }

    res.json({
      success: true,
      data,
    });
  } catch (error) {
    console.error('Error fetching submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch submission',
    });
  }
});

/**
 * PATCH /api/contact/submissions/:id
 * Update a contact form submission status
 */
router.patch('/submissions/:id',
  rateLimiters.api,  // Apply general API rate limiting
  sanitizeRequestBody,  // Sanitize input
  async (req, res) => {
  try {
    // TODO: Add authentication check here

    const { status, assignedTo, notes } = req.body;

    const updateData = {};
    if (status) updateData.status = status;
    if (assignedTo !== undefined) updateData.assigned_to = assignedTo;
    if (notes !== undefined) updateData.notes = notes;
    if (status === 'responded') updateData.responded_at = new Date().toISOString();

    const { data, error } = await supabase
      .from('contact.contact_inquiries')  // Using the correct table
      .update(updateData)
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(404).json({
          success: false,
          error: 'Submission not found',
        });
      }
      throw error;
    }

    res.json({
      success: true,
      data,
    });
  } catch (error) {
    console.error('Error updating submission:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update submission',
    });
  }
});

/**
 * Helper function to send email via SendGrid
 */
async function sendEmail({ to, subject, html, text, replyTo }) {
  try {
    const msg = {
      to,
      from: {
        email: process.env.EMAIL_FROM || 'hello@dinkhousepb.com',
        name: 'The Dink House',
      },
      subject,
      html,
      text: text || stripHtml(html),
    };

    if (replyTo) {
      msg.replyTo = replyTo;
    }

    await sgMail.send(msg);
    return true;
  } catch (error) {
    console.error('SendGrid error:', error);
    throw error;
  }
}

/**
 * Helper function to replace template variables
 */
function replaceVariables(template, variables) {
  let result = template;

  // Replace simple variables
  Object.keys(variables).forEach((key) => {
    const regex = new RegExp(`{{${key}}}`, 'g');
    result = result.replace(regex, variables[key] || '');
  });

  // Handle conditionals
  result = result.replace(/{{#if (\w+)}}([\s\S]*?){{\/if}}/g, (match, varName, content) => {
    return variables[varName] ? content : '';
  });

  return result;
}

/**
 * Helper function to strip HTML tags
 */
function stripHtml(html) {
  return html.replace(/<[^>]*>/g, '').trim();
}

module.exports = router;