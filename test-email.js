const path = require('path');
const dotenv = require('dotenv');

// Ensure environment variables (especially NODE_ENV/SMTP_*) are loaded before we import the email utility
dotenv.config({ path: path.resolve(__dirname, '.env') });
process.env.NODE_ENV = process.env.NODE_ENV || 'development';
process.env.SMTP_HOST = process.env.SMTP_HOST || 'localhost';
process.env.SMTP_PORT = process.env.SMTP_PORT || '1025';

const { sendEmail } = require('./api/utils/email');

async function testEmails() {
  console.log('Sending test emails...');
  
  // Test welcome email
  console.log('Sending welcome email...');
  const welcomeResult = await sendEmail('test@example.com', 'welcome', { 
    name: 'Test User' 
  });
  console.log('Welcome email result:', welcomeResult);

  // Test notification email
  console.log('\nSending notification email...');
  const notificationResult = await sendEmail('test@example.com', 'notification', {
    title: 'Test Event',
    message: 'This is a test notification from the email system.'
  });
  console.log('Notification email result:', notificationResult);
}

// Run the test
testEmails()
  .then(() => console.log('\nTest completed! Check Mailpit at http://localhost:8025'))
  .catch(console.error);
