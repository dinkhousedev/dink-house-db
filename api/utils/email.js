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
  })
};

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
