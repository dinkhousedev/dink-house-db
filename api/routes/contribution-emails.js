const express = require('express');
const router = express.Router();
const { sendEmail } = require('../utils/email');
const { supabase } = require('../config/supabase.config');

/**
 * Send contribution thank you email
 * POST /api/contribution-emails/send-thank-you
 * Body: { contribution_id: "uuid" }
 *
 * This endpoint is typically called by:
 * 1. Stripe webhook after successful payment
 * 2. Admin dashboard for manual resends
 * 3. Scheduled job to process pending emails
 */
router.post('/send-thank-you', async (req, res) => {
  try {
    const { contribution_id } = req.body;

    if (!contribution_id) {
      return res.status(400).json({
        success: false,
        error: 'contribution_id is required'
      });
    }

    // Call database function to prepare email data
    const { data: emailResult, error: dbError } = await supabase
      .rpc('send_contribution_thank_you_email', {
        p_contribution_id: contribution_id
      });

    if (dbError) {
      console.error('Database error preparing email:', dbError);
      return res.status(500).json({
        success: false,
        error: 'Failed to prepare email',
        details: dbError.message
      });
    }

    if (!emailResult?.success) {
      return res.status(400).json({
        success: false,
        error: emailResult?.error || 'Failed to prepare email',
        message: emailResult?.message
      });
    }

    // Send the email using the email utility
    const emailData = emailResult.email_data;
    const sendResult = await sendEmail(
      emailResult.recipient,
      'contributionThankYou',
      emailData
    );

    if (!sendResult.success) {
      // Update email log to 'failed' status
      await supabase
        .from('email_logs')
        .update({
          status: 'failed',
          error_message: sendResult.message || sendResult.error
        })
        .eq('id', emailResult.email_log_id);

      return res.status(500).json({
        success: false,
        error: 'Failed to send email',
        details: sendResult.message
      });
    }

    // Update email log to 'sent' status
    await supabase
      .from('email_logs')
      .update({
        status: 'sent',
        sent_at: new Date().toISOString(),
        provider_message_id: sendResult.messageId
      })
      .eq('id', emailResult.email_log_id);

    res.json({
      success: true,
      message: 'Contribution thank you email sent successfully',
      email_log_id: emailResult.email_log_id,
      recipient: emailResult.recipient,
      messageId: sendResult.messageId
    });

  } catch (error) {
    console.error('Error sending contribution thank you email:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message
    });
  }
});

/**
 * Process pending contribution emails
 * POST /api/contribution-emails/process-pending
 *
 * This endpoint processes all pending contribution thank you emails.
 * Can be called by a scheduled job (cron) or manually.
 */
router.post('/process-pending', async (req, res) => {
  try {
    // Get all pending contribution thank you emails
    const { data: pendingEmails, error: fetchError } = await supabase
      .from('email_logs')
      .select('id, to_email, metadata')
      .eq('template_key', 'contribution_thank_you')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(50); // Process in batches of 50

    if (fetchError) {
      console.error('Error fetching pending emails:', fetchError);
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch pending emails',
        details: fetchError.message
      });
    }

    if (!pendingEmails || pendingEmails.length === 0) {
      return res.json({
        success: true,
        message: 'No pending emails to process',
        processed: 0
      });
    }

    const results = {
      total: pendingEmails.length,
      sent: 0,
      failed: 0,
      errors: []
    };

    // Process each email
    for (const emailLog of pendingEmails) {
      try {
        const contributionId = emailLog.metadata?.contribution_id;

        if (!contributionId) {
          console.warn(`Email log ${emailLog.id} missing contribution_id`);
          results.failed++;
          continue;
        }

        // Prepare email data by calling the database function
        const { data: emailResult, error: dbError } = await supabase
          .rpc('send_contribution_thank_you_email', {
            p_contribution_id: contributionId
          });

        if (dbError || !emailResult?.success) {
          console.error(`Failed to prepare email for contribution ${contributionId}:`, dbError);
          results.failed++;
          results.errors.push({
            contribution_id: contributionId,
            error: dbError?.message || emailResult?.error
          });
          continue;
        }

        // Send the email
        const emailData = emailResult.email_data;
        const sendResult = await sendEmail(
          emailLog.to_email,
          'contributionThankYou',
          emailData
        );

        if (sendResult.success) {
          // Update to 'sent'
          await supabase
            .from('email_logs')
            .update({
              status: 'sent',
              sent_at: new Date().toISOString(),
              provider_message_id: sendResult.messageId
            })
            .eq('id', emailLog.id);

          results.sent++;
        } else {
          // Update to 'failed'
          await supabase
            .from('email_logs')
            .update({
              status: 'failed',
              error_message: sendResult.message || sendResult.error
            })
            .eq('id', emailLog.id);

          results.failed++;
          results.errors.push({
            email_log_id: emailLog.id,
            error: sendResult.message
          });
        }

      } catch (emailError) {
        console.error(`Error processing email ${emailLog.id}:`, emailError);
        results.failed++;
        results.errors.push({
          email_log_id: emailLog.id,
          error: emailError.message
        });
      }
    }

    res.json({
      success: true,
      message: `Processed ${results.total} pending emails`,
      results
    });

  } catch (error) {
    console.error('Error processing pending emails:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message
    });
  }
});

/**
 * Resend contribution email (manual trigger)
 * POST /api/contribution-emails/resend
 * Body: { contribution_id: "uuid" }
 *
 * Forces a resend of the thank you email for a specific contribution.
 * Useful for customer support or when the original email failed.
 */
router.post('/resend', async (req, res) => {
  try {
    const { contribution_id } = req.body;

    if (!contribution_id) {
      return res.status(400).json({
        success: false,
        error: 'contribution_id is required'
      });
    }

    // Verify contribution exists and is completed
    const { data: contribution, error: contribError } = await supabase
      .from('contributions')
      .select('id, status, completed_at, backer_id')
      .eq('id', contribution_id)
      .single();

    if (contribError || !contribution) {
      return res.status(404).json({
        success: false,
        error: 'Contribution not found'
      });
    }

    if (contribution.status !== 'completed') {
      return res.status(400).json({
        success: false,
        error: 'Contribution is not completed yet'
      });
    }

    // Call the send endpoint
    return router.handle({
      ...req,
      body: { contribution_id }
    }, res);

  } catch (error) {
    console.error('Error resending contribution email:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
      details: error.message
    });
  }
});

module.exports = router;
