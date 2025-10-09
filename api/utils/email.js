const nodemailer = require('nodemailer');
const config = require('../config/supabase.config');

// Create a transporter instance based on environment
const transporter = nodemailer.createTransport({
  host: config.email.smtp.host,
  port: config.email.smtp.port,
  secure: config.email.smtp.secure,
  auth: config.email.smtp.auth,
  tls: {
    // Do not fail on invalid certs for local development
    rejectUnauthorized: process.env.NODE_ENV !== 'development'
  }
});

// Email templates
const templates = {
  welcome: (data) => ({
    subject: 'Welcome to Dink House!',
    html: `
      <h1>Welcome to Dink House, ${data.name}!</h1>
      <p>We're excited to have you on board.</p>
    `,
    text: `Welcome to Dink House, ${data.name}!\n\nWe're excited to have you on board.`
  }),
  notification: (data) => ({
    subject: `New Notification: ${data.title}`,
    html: `
      <h1>${data.title}</h1>
      <p>${data.message}</p>
    `,
    text: `${data.title}\n\n${data.message}`
  }),
  contributionThankYou: (data) => {
    // This template fetches the HTML/text from the database template
    // The database function sends_contribution_thank_you_email handles the actual rendering
    return {
      subject: `Thank You for Your Contribution to The Dink House! 🎉`,
      html: renderContributionThankYouHTML(data),
      text: renderContributionThankYouText(data)
    };
  }
};

// Helper function to render contribution thank you HTML
function renderContributionThankYouHTML(data) {
  const {
    first_name,
    amount,
    tier_name,
    contribution_date,
    contribution_id,
    payment_method,
    stripe_charge_id,
    benefits_html,
    on_founders_wall,
    display_name,
    founders_wall_message,
    site_url = 'https://thedinkhouse.com'
  } = data;

  const foundersWallSection = on_founders_wall ? `
    <div class="recognition-box">
      <h3>🌟 You're on the Founders Wall!</h3>
      <p>Your name will be displayed as: <strong>${display_name}</strong></p>
      <p style="margin-top: 8px;">${founders_wall_message}</p>
    </div>
  ` : '';

  return `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background-color: #f5f5f5; }
    .container { max-width: 650px; margin: 0 auto; background-color: #ffffff; }
    .header { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 40px 30px; text-align: center; }
    .logo { max-width: 200px; height: auto; margin-bottom: 15px; }
    .header h1 { color: #1a1a1a; margin: 0; font-size: 28px; font-weight: 700; }
    .content { padding: 40px 35px; }
    .greeting { font-size: 18px; margin-bottom: 20px; }
    .section { margin: 30px 0; padding: 25px; background: #f9f9f9; border-radius: 8px; border-left: 4px solid #B3FF00; }
    .section-title { font-size: 20px; font-weight: 700; color: #1a1a1a; margin: 0 0 15px 0; display: flex; align-items: center; }
    .section-title .icon { margin-right: 10px; font-size: 24px; }
    .receipt-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 15px; }
    .receipt-label { font-size: 12px; text-transform: uppercase; color: #666; font-weight: 600; letter-spacing: 0.5px; margin-bottom: 5px; }
    .receipt-value { font-size: 16px; color: #1a1a1a; font-weight: 600; }
    .receipt-value.amount { font-size: 24px; color: #B3FF00; font-weight: 700; }
    .benefits-list { margin-top: 15px; }
    .benefit-item { background: white; padding: 15px; margin: 10px 0; border-radius: 6px; border: 1px solid #e0e0e0; display: flex; align-items: start; }
    .benefit-item .checkmark { color: #B3FF00; font-size: 20px; margin-right: 12px; font-weight: bold; }
    .benefit-content { flex: 1; }
    .benefit-name { font-weight: 600; color: #1a1a1a; font-size: 15px; margin-bottom: 3px; }
    .benefit-details { font-size: 13px; color: #666; }
    .benefit-quantity { display: inline-block; background: #B3FF00; color: #1a1a1a; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: 600; margin-left: 8px; }
    .recognition-box { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0; }
    .recognition-box h3 { margin: 0 0 10px 0; color: #1a1a1a; font-size: 18px; }
    .recognition-box p { margin: 0; color: #1a1a1a; font-size: 14px; }
    .cta-box { text-align: center; margin: 30px 0; }
    .button { display: inline-block; background: #B3FF00; color: #1a1a1a; padding: 14px 32px; text-decoration: none; border-radius: 6px; font-weight: 700; font-size: 16px; }
    .help-text { background: #f0f0f0; padding: 20px; border-radius: 6px; margin: 25px 0; font-size: 14px; color: #666; }
    .footer { background: #1a1a1a; color: #ffffff; padding: 30px 35px; text-align: center; font-size: 14px; }
    .footer a { color: #B3FF00; text-decoration: none; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg" alt="The Dink House" class="logo" />
      <h1>Thank You for Your Contribution!</h1>
    </div>
    <div class="content">
      <p class="greeting">Hi ${first_name},</p>
      <p style="font-size: 16px; line-height: 1.8;">
        🎉 <strong>Wow!</strong> We are absolutely thrilled and grateful for your generous contribution to The Dink House.
        You're not just supporting a pickleball facility—you're helping build a community where players of all levels can thrive, learn, and connect.
      </p>
      <div class="section">
        <h2 class="section-title"><span class="icon">📄</span> Your Receipt</h2>
        <div class="receipt-grid">
          <div><div class="receipt-label">Contribution Amount</div><div class="receipt-value amount">$${amount}</div></div>
          <div><div class="receipt-label">Contribution Tier</div><div class="receipt-value">${tier_name}</div></div>
          <div><div class="receipt-label">Date</div><div class="receipt-value">${contribution_date}</div></div>
          <div><div class="receipt-label">Transaction ID</div><div class="receipt-value" style="font-size: 13px;">${contribution_id}</div></div>
          <div><div class="receipt-label">Payment Method</div><div class="receipt-value">${payment_method}</div></div>
          <div><div class="receipt-label">Stripe Charge ID</div><div class="receipt-value" style="font-size: 12px;">${stripe_charge_id}</div></div>
        </div>
      </div>
      <div class="section">
        <h2 class="section-title"><span class="icon">🎁</span> Your Rewards & Benefits</h2>
        <p style="margin-top: 0; color: #666;">As a valued contributor, you're receiving the following benefits:</p>
        <div class="benefits-list">${benefits_html}</div>
      </div>
      ${foundersWallSection}
      <div class="help-text">
        <strong>📋 Next Steps:</strong><br>
        • Keep this email for your records - it serves as your official receipt<br>
        • Benefits will be available once The Dink House opens<br>
        • Watch your email for facility updates and opening announcements<br>
        • Questions? Reply to this email or call us at (254) 123-4567
      </div>
      <div class="cta-box">
        <a href="${site_url}" class="button">Visit The Dink House</a>
      </div>
      <p style="font-size: 16px; margin-top: 40px;">
        Your support means the world to us. Together, we're creating something special for the pickleball community in Bell County!
      </p>
      <p style="font-size: 16px; font-weight: 600;">
        With gratitude,<br>The Dink House Team
      </p>
    </div>
    <div class="footer">
      <p><strong>The Dink House</strong> - Where Pickleball Lives</p>
      <p style="margin-top: 15px; font-size: 13px; color: #999;">
        Questions? Contact us at support@thedinkhouse.com or (254) 123-4567<br>
        <span style="font-size: 11px; margin-top: 10px; display: block;">
          This is a receipt for your contribution. Please keep for your records.
        </span>
      </p>
    </div>
  </div>
</body>
</html>
  `;
}

// Helper function to render contribution thank you plain text
function renderContributionThankYouText(data) {
  const {
    first_name,
    amount,
    tier_name,
    contribution_date,
    contribution_id,
    payment_method,
    stripe_charge_id,
    benefits_text,
    on_founders_wall,
    display_name,
    founders_wall_message,
    site_url = 'https://thedinkhouse.com'
  } = data;

  const foundersWallSection = on_founders_wall ? `
=====================================
🌟 FOUNDERS WALL RECOGNITION
=====================================

Your name will be displayed as: ${display_name}
${founders_wall_message}
` : '';

  return `Hi ${first_name},

🎉 THANK YOU FOR YOUR CONTRIBUTION! 🎉

We are absolutely thrilled and grateful for your generous contribution to The Dink House. You're not just supporting a pickleball facility—you're helping build a community where players of all levels can thrive, learn, and connect.

=====================================
YOUR RECEIPT
=====================================

Contribution Amount: $${amount}
Contribution Tier: ${tier_name}
Date: ${contribution_date}
Transaction ID: ${contribution_id}
Payment Method: ${payment_method}
Stripe Charge ID: ${stripe_charge_id}

=====================================
YOUR REWARDS & BENEFITS
=====================================

As a valued contributor, you're receiving:

${benefits_text}
${foundersWallSection}
=====================================
NEXT STEPS
=====================================

• Keep this email for your records - it serves as your official receipt
• Benefits will be available once The Dink House opens
• Watch your email for facility updates and opening announcements
• Questions? Reply to this email or call us at (254) 123-4567

Visit us at: ${site_url}

Your support means the world to us. Together, we're creating something special for the pickleball community in Bell County!

With gratitude,
The Dink House Team

--
The Dink House - Where Pickleball Lives
Questions? Contact us at support@thedinkhouse.com or (254) 123-4567

This is a receipt for your contribution. Please keep for your records.
`;
}

/**
 * Send an email using the specified template
 * @param {string} to - Recipient email address
 * @param {string} templateName - Name of the template to use
 * @param {Object} data - Data to inject into the template
 * @param {Object} options - Additional email options (cc, bcc, attachments, etc.)
 */
const sendEmail = async (to, templateName, data = {}, options = {}) => {
  if (!config.email.enabled) {
    console.warn('Email sending is disabled. Enable it in the configuration.');
    return { success: false, message: 'Email sending is disabled' };
  }

  const template = templates[templateName];
  if (!template) {
    throw new Error(`Template '${templateName}' not found`);
  }

  const templateData = template(data);
  
  const mailOptions = {
    from: config.email.from,
    to,
    subject: templateData.subject,
    html: templateData.html,
    text: templateData.text,
    ...options
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    console.log('Email sent:', info.messageId);
    return { 
      success: true, 
      message: 'Email sent successfully',
      messageId: info.messageId 
    };
  } catch (error) {
    console.error('Error sending email:', error);
    return { 
      success: false, 
      message: 'Failed to send email',
      error: error.message 
    };
  }
};

module.exports = {
  sendEmail,
  templates: Object.keys(templates)
};
