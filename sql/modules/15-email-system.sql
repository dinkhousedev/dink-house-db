-- ============================================================================
-- EMAIL SYSTEM MODULE
-- Email templates, logs, and asset management
-- ============================================================================

-- Note: uuid-ossp extension should already be installed in Supabase Cloud

-- Create system schema if not exists
CREATE SCHEMA IF NOT EXISTS system;

-- Set search path
SET search_path TO system, public;

-- Email templates table
CREATE TABLE IF NOT EXISTS system.email_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    subject VARCHAR(255) NOT NULL,
    html_body TEXT NOT NULL,
    text_body TEXT,
    variables JSONB DEFAULT '[]',
    category VARCHAR(50) DEFAULT 'general',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Email logs table
CREATE TABLE IF NOT EXISTS system.email_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key VARCHAR(100) REFERENCES system.email_templates(template_key) ON DELETE SET NULL,
    to_email TEXT NOT NULL,
    from_email TEXT NOT NULL,
    subject VARCHAR(255),
    status VARCHAR(50) DEFAULT 'pending'
        CHECK (status IN ('pending', 'sent', 'failed', 'bounced', 'opened', 'clicked')),
    provider VARCHAR(50) DEFAULT 'sendgrid',
    provider_message_id VARCHAR(255),
    metadata JSONB DEFAULT '{}',
    error_message TEXT,
    sent_at TIMESTAMP WITH TIME ZONE,
    opened_at TIMESTAMP WITH TIME ZONE,
    clicked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Email attachments table
CREATE TABLE IF NOT EXISTS system.email_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_log_id UUID REFERENCES system.email_logs(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes INTEGER,
    storage_path TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX email_logs_to_email ON system.email_logs(to_email);
CREATE INDEX email_logs_status ON system.email_logs(status);
CREATE INDEX email_logs_created_at ON system.email_logs(created_at);
CREATE INDEX email_logs_template_key ON system.email_logs(template_key);

-- Insert default email templates
INSERT INTO system.email_templates (template_key, name, subject, html_body, text_body, category, variables) VALUES
(
    'contact_form_thank_you',
    'Contact Form - Thank You',
    'Thank you for contacting The Dink House',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 40px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { max-width: 200px; height: auto; margin-bottom: 20px; }
        .content { background: #ffffff; padding: 40px 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #CDFE00; color: #000; padding: 14px 30px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-top: 20px; }
        .footer { text-align: center; padding: 30px; color: #666; font-size: 14px; }
        .social-links { margin-top: 20px; }
        .social-links a { margin: 0 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="{{logo_url}}" alt="The Dink House" class="logo" />
            <h1 style="color: white; margin: 0; font-size: 28px;">Thank You for Reaching Out!</h1>
        </div>
        <div class="content">
            <p style="font-size: 16px;">Hi {{first_name}},</p>

            <p>Thank you for contacting The Dink House! We''ve received your message and truly appreciate you taking the time to reach out to us.</p>

            <p>Our team is reviewing your inquiry and will get back to you within 24-48 hours. We''re excited to connect with you and discuss how we can help with your pickleball needs!</p>

            <p>In the meantime, feel free to:</p>
            <ul>
                <li>Check out our latest updates on social media</li>
                <li>Browse our facilities and programs on our website</li>
                <li>Join our community of pickleball enthusiasts</li>
            </ul>

            <center>
                <a href="{{site_url}}" class="button">Visit Our Website</a>
            </center>

            <p style="margin-top: 30px;">If you have any urgent questions, feel free to call us at (555) 123-4567.</p>

            <p>Looking forward to connecting with you soon!</p>

            <p><strong>Best regards,<br>The Dink House Team</strong></p>
        </div>
        <div class="footer">
            <p>The Dink House - Where Pickleball Lives</p>
            <div class="social-links">
                <a href="#">Facebook</a> |
                <a href="#">Instagram</a> |
                <a href="#">Twitter</a>
            </div>
            <p style="font-size: 12px; margin-top: 20px;">
                © 2025 The Dink House. All rights reserved.<br>
                123 Pickleball Lane, Your City, ST 12345
            </p>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

Thank you for contacting The Dink House! We''ve received your message and truly appreciate you taking the time to reach out to us.

Our team is reviewing your inquiry and will get back to you within 24-48 hours. We''re excited to connect with you and discuss how we can help with your pickleball needs!

If you have any urgent questions, feel free to call us at (555) 123-4567.

Looking forward to connecting with you soon!

Best regards,
The Dink House Team

--
The Dink House - Where Pickleball Lives
Visit us at: {{site_url}}',
    'contact',
    '["first_name", "site_url", "logo_url"]'::jsonb
),
(
    'contact_form_admin',
    'Contact Form - Admin Notification',
    'New Contact Form Submission - {{subject}}',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 700px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 30px; border-radius: 8px 8px 0 0; }
        .content { background: #f9f9f9; padding: 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .field { margin-bottom: 25px; background: white; padding: 15px; border-radius: 4px; border: 1px solid #e0e0e0; }
        .label { font-weight: 600; color: #666; margin-bottom: 8px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        .value { color: #333; font-size: 15px; }
        .message-box { background: white; padding: 20px; border-radius: 4px; border: 1px solid #e0e0e0; white-space: pre-wrap; }
        .metadata { margin-top: 30px; padding-top: 20px; border-top: 2px solid #e0e0e0; }
        .button { display: inline-block; background: #CDFE00; color: #000; padding: 12px 24px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-right: 10px; }
        .button-secondary { background: #f0f0f0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2 style="color: white; margin: 0;">New Contact Form Submission</h2>
            <p style="color: rgba(255,255,255,0.9); margin: 10px 0 0 0;">Received at {{submitted_at}}</p>
        </div>
        <div class="content">
            <div class="field">
                <div class="label">Name</div>
                <div class="value">{{first_name}} {{last_name}}</div>
            </div>

            <div class="field">
                <div class="label">Email</div>
                <div class="value"><a href="mailto:{{email}}">{{email}}</a></div>
            </div>

            {{#if phone}}
            <div class="field">
                <div class="label">Phone</div>
                <div class="value">{{phone}}</div>
            </div>
            {{/if}}

            {{#if company}}
            <div class="field">
                <div class="label">Company</div>
                <div class="value">{{company}}</div>
            </div>
            {{/if}}

            {{#if subject}}
            <div class="field">
                <div class="label">Subject</div>
                <div class="value">{{subject}}</div>
            </div>
            {{/if}}

            <div class="field">
                <div class="label">Message</div>
                <div class="message-box">{{message}}</div>
            </div>

            <div style="margin-top: 30px;">
                <a href="{{admin_url}}" class="button">View in Admin</a>
                <a href="mailto:{{email}}" class="button button-secondary">Reply via Email</a>
            </div>

            <div class="metadata">
                <p style="color: #999; font-size: 13px;">
                    <strong>Submission ID:</strong> {{submission_id}}<br>
                    <strong>Form Type:</strong> {{form_type}}<br>
                    <strong>Submitted:</strong> {{submitted_at}}
                </p>
            </div>
        </div>
    </div>
</body>
</html>',
    'New Contact Form Submission

Name: {{first_name}} {{last_name}}
Email: {{email}}
Phone: {{phone}}
Company: {{company}}
Subject: {{subject}}

Message:
{{message}}

--
Submission ID: {{submission_id}}
Submitted: {{submitted_at}}
View in Admin: {{admin_url}}',
    'contact',
    '["first_name", "last_name", "email", "phone", "company", "subject", "message", "submission_id", "submitted_at", "admin_url", "form_type"]'::jsonb
),
(
    'welcome_email',
    'Welcome Email',
    'Welcome to The Dink House Community!',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #CDFE00 0%, #9BCF00 100%); padding: 50px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { max-width: 250px; height: auto; margin-bottom: 20px; }
        .content { background: #ffffff; padding: 40px 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #CDFE00; color: #000; padding: 16px 40px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-top: 20px; font-size: 16px; }
        .features { margin: 30px 0; }
        .feature { padding: 15px; margin: 10px 0; background: #f8f8f8; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="{{logo_url}}" alt="The Dink House" class="logo" />
            <h1 style="color: white; margin: 0; font-size: 32px;">Welcome to The Dink House!</h1>
        </div>
        <div class="content">
            <p style="font-size: 18px;">Hi {{first_name}},</p>

            <p style="font-size: 16px;">Welcome to The Dink House community! We''re thrilled to have you join our growing family of pickleball enthusiasts.</p>

            <div class="features">
                <h3>Here''s what you can look forward to:</h3>
                <div class="feature">
                    <strong>🏓 World-Class Facilities</strong><br>
                    Professional courts, equipment, and amenities
                </div>
                <div class="feature">
                    <strong>👥 Vibrant Community</strong><br>
                    Connect with players of all skill levels
                </div>
                <div class="feature">
                    <strong>📅 Events & Tournaments</strong><br>
                    Regular competitions and social events
                </div>
                <div class="feature">
                    <strong>🎓 Professional Coaching</strong><br>
                    Improve your game with expert instruction
                </div>
            </div>

            <center>
                <a href="{{site_url}}/get-started" class="button">Get Started</a>
            </center>

            <p style="margin-top: 40px;">If you have any questions, our team is here to help. Just reply to this email or give us a call.</p>

            <p><strong>See you on the courts!<br>The Dink House Team</strong></p>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

Welcome to The Dink House community! We''re thrilled to have you join our growing family of pickleball enthusiasts.

Here''s what you can look forward to:

🏓 World-Class Facilities - Professional courts, equipment, and amenities
👥 Vibrant Community - Connect with players of all skill levels
📅 Events & Tournaments - Regular competitions and social events
🎓 Professional Coaching - Improve your game with expert instruction

Get started at: {{site_url}}/get-started

If you have any questions, our team is here to help. Just reply to this email or give us a call.

See you on the courts!
The Dink House Team',
    'user',
    '["first_name", "site_url", "logo_url"]'::jsonb
),
(
    'newsletter_welcome',
    'Newsletter Welcome Email',
    'Welcome to The Dink House Newsletter!',
    '<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 50px 20px; text-align: center; border-radius: 8px 8px 0 0; }
        .logo { max-width: 200px; height: auto; margin-bottom: 20px; }
        .content { background: #ffffff; padding: 40px 30px; border: 1px solid #e0e0e0; border-top: none; border-radius: 0 0 8px 8px; }
        .button { display: inline-block; background: #B3FF00; color: #000; padding: 16px 40px; text-decoration: none; border-radius: 4px; font-weight: 600; margin-top: 20px; font-size: 16px; }
        .benefits { margin: 30px 0; }
        .benefit { padding: 15px; margin: 10px 0; background: #f8f8f8; border-radius: 4px; border-left: 4px solid #B3FF00; }
        .footer { text-align: center; padding: 30px; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg" alt="The Dink House" class="logo" />
            <h1 style="color: white; margin: 0; font-size: 32px;">You''re In!</h1>
        </div>
        <div class="content">
            <p style="font-size: 18px;">Hi {{first_name}},</p>

            <p style="font-size: 16px;">Thank you for subscribing to The Dink House newsletter! You''re now part of an exclusive community of pickleball enthusiasts who get first access to:</p>

            <div class="benefits">
                <div class="benefit">
                    <strong>🏓 Early Access</strong><br>
                    Be the first to know about court bookings and new facilities
                </div>
                <div class="benefit">
                    <strong>🎉 Exclusive Events</strong><br>
                    VIP invitations to tournaments, clinics, and social gatherings
                </div>
                <div class="benefit">
                    <strong>💡 Pro Tips & Insights</strong><br>
                    Expert advice to improve your game from our coaches
                </div>
                <div class="benefit">
                    <strong>🎁 Special Offers</strong><br>
                    Member-only discounts on bookings, gear, and programs
                </div>
            </div>

            <p>We''re working hard to create the ultimate pickleball destination, and we can''t wait to share our progress with you!</p>

            <center>
                <a href="{{site_url}}" class="button">Visit The Dink House</a>
            </center>

            <p style="margin-top: 40px; font-size: 14px; color: #666;">
                PS: Keep an eye on your inbox - we have some exciting announcements coming soon!
            </p>

            <p><strong>See you soon,<br>The Dink House Team</strong></p>
        </div>
        <div class="footer">
            <p>The Dink House - Where Pickleball Lives</p>
            <p style="font-size: 12px; margin-top: 20px; color: #999;">
                You''re receiving this because you subscribed to our newsletter at {{site_url}}
            </p>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

Thank you for subscribing to The Dink House newsletter! You''re now part of an exclusive community of pickleball enthusiasts.

You''ll be the first to know about:
🏓 Early Access - Court bookings and new facilities
🎉 Exclusive Events - Tournaments, clinics, and social gatherings
💡 Pro Tips - Expert advice from our coaches
🎁 Special Offers - Member-only discounts

We''re working hard to create the ultimate pickleball destination, and we can''t wait to share our progress with you!

Visit us at: {{site_url}}

See you soon,
The Dink House Team

--
The Dink House - Where Pickleball Lives
You''re receiving this because you subscribed to our newsletter.',
    'newsletter',
    '["first_name", "email", "site_url", "logo_url"]'::jsonb
),
(
    'contribution_thank_you',
    'Contribution Thank You with Receipt',
    'Thank You for Your Contribution to The Dink House! 🎉',
    '<!DOCTYPE html>
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
        .receipt-item { }
        .receipt-label { font-size: 12px; text-transform: uppercase; color: #666; font-weight: 600; letter-spacing: 0.5px; margin-bottom: 5px; }
        .receipt-value { font-size: 16px; color: #1a1a1a; font-weight: 600; }
        .receipt-value.amount { font-size: 24px; color: #B3FF00; text-shadow: 1px 1px 2px rgba(0,0,0,0.1); background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }

        .benefits-list { margin-top: 15px; }
        .benefit-item { background: white; padding: 15px; margin: 10px 0; border-radius: 6px; border: 1px solid #e0e0e0; display: flex; align-items: start; }
        .benefit-item .checkmark { color: #B3FF00; font-size: 20px; margin-right: 12px; font-weight: bold; flex-shrink: 0; }
        .benefit-content { flex: 1; }
        .benefit-name { font-weight: 600; color: #1a1a1a; font-size: 15px; margin-bottom: 3px; }
        .benefit-details { font-size: 13px; color: #666; }
        .benefit-quantity { display: inline-block; background: #B3FF00; color: #1a1a1a; padding: 2px 8px; border-radius: 12px; font-size: 12px; font-weight: 600; margin-left: 8px; }

        .recognition-box { background: linear-gradient(135deg, #B3FF00 0%, #9BCF00 100%); padding: 20px; border-radius: 8px; text-align: center; margin: 20px 0; }
        .recognition-box h3 { margin: 0 0 10px 0; color: #1a1a1a; font-size: 18px; }
        .recognition-box p { margin: 0; color: #1a1a1a; font-size: 14px; }

        .cta-box { text-align: center; margin: 30px 0; }
        .button { display: inline-block; background: #B3FF00; color: #1a1a1a; padding: 14px 32px; text-decoration: none; border-radius: 6px; font-weight: 700; font-size: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .button:hover { background: #9BCF00; }

        .help-text { background: #f0f0f0; padding: 20px; border-radius: 6px; margin: 25px 0; font-size: 14px; color: #666; }

        .footer { background: #1a1a1a; color: #ffffff; padding: 30px 35px; text-align: center; font-size: 14px; }
        .footer a { color: #B3FF00; text-decoration: none; }
        .footer .social-links { margin: 15px 0; }
        .footer .contact { margin-top: 20px; font-size: 13px; color: #999; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="https://wchxzbuuwssrnaxshseu.supabase.co/storage/v1/object/public/dink-files/dinklogo.jpg" alt="The Dink House" class="logo" />
            <h1>Thank You for Your Contribution!</h1>
        </div>

        <div class="content">
            <p class="greeting">Hi {{first_name}},</p>

            <p style="font-size: 16px; line-height: 1.8;">
                🎉 <strong>Wow!</strong> We are absolutely thrilled and grateful for your generous contribution to The Dink House.
                You''re not just supporting a pickleball facility—you''re helping build a community where players of all levels can thrive, learn, and connect.
            </p>

            <!-- Receipt Section -->
            <div class="section">
                <h2 class="section-title">
                    <span class="icon">📄</span>
                    Your Receipt
                </h2>
                <div class="receipt-grid">
                    <div class="receipt-item">
                        <div class="receipt-label">Contribution Amount</div>
                        <div class="receipt-value amount">${{amount}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Contribution Tier</div>
                        <div class="receipt-value">{{tier_name}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Date</div>
                        <div class="receipt-value">{{contribution_date}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Transaction ID</div>
                        <div class="receipt-value" style="font-size: 13px;">{{contribution_id}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Payment Method</div>
                        <div class="receipt-value">{{payment_method}}</div>
                    </div>
                    <div class="receipt-item">
                        <div class="receipt-label">Stripe Charge ID</div>
                        <div class="receipt-value" style="font-size: 12px;">{{stripe_charge_id}}</div>
                    </div>
                </div>
            </div>

            <!-- Rewards Section -->
            <div class="section">
                <h2 class="section-title">
                    <span class="icon">🎁</span>
                    Your Rewards & Benefits
                </h2>
                <p style="margin-top: 0; color: #666;">As a valued contributor, you''re receiving the following benefits:</p>
                <div class="benefits-list">
                    {{benefits_html}}
                </div>
            </div>

            <!-- Founders Wall Recognition -->
            {{#if on_founders_wall}}
            <div class="recognition-box">
                <h3>🌟 You''re on the Founders Wall!</h3>
                <p>Your name will be displayed as: <strong>{{display_name}}</strong></p>
                <p style="margin-top: 8px;">{{founders_wall_message}}</p>
            </div>
            {{/if}}

            <!-- Next Steps -->
            <div class="help-text">
                <strong>📋 Next Steps:</strong><br>
                • Keep this email for your records - it serves as your official receipt<br>
                • Benefits will be available once The Dink House opens<br>
                • Watch your email for facility updates and opening announcements<br>
                • Questions? Reply to this email or call us at (254) 123-4567
            </div>

            <div class="cta-box">
                <a href="{{site_url}}" class="button">Visit The Dink House</a>
            </div>

            <p style="font-size: 16px; margin-top: 40px;">
                Your support means the world to us. Together, we''re creating something special for the pickleball community in Bell County!
            </p>

            <p style="font-size: 16px; font-weight: 600;">
                With gratitude,<br>
                The Dink House Team
            </p>
        </div>

        <div class="footer">
            <p><strong>The Dink House</strong> - Where Pickleball Lives</p>
            <div class="social-links">
                <a href="#">Facebook</a> | <a href="#">Instagram</a> | <a href="#">Twitter</a>
            </div>
            <div class="contact">
                Questions? Contact us at support@thedinkhouse.com or (254) 123-4567<br>
                <span style="font-size: 11px; margin-top: 10px; display: block;">
                    This is a receipt for your contribution. Please keep for your records.<br>
                    The Dink House is a project of [Organization Name]. Contributions may be tax-deductible - consult your tax advisor.
                </span>
            </div>
        </div>
    </div>
</body>
</html>',
    'Hi {{first_name}},

🎉 THANK YOU FOR YOUR CONTRIBUTION! 🎉

We are absolutely thrilled and grateful for your generous contribution to The Dink House. You''re not just supporting a pickleball facility—you''re helping build a community where players of all levels can thrive, learn, and connect.

=====================================
YOUR RECEIPT
=====================================

Contribution Amount: ${{amount}}
Contribution Tier: {{tier_name}}
Date: {{contribution_date}}
Transaction ID: {{contribution_id}}
Payment Method: {{payment_method}}
Stripe Charge ID: {{stripe_charge_id}}

=====================================
YOUR REWARDS & BENEFITS
=====================================

As a valued contributor, you''re receiving:

{{benefits_text}}

{{#if on_founders_wall}}
=====================================
🌟 FOUNDERS WALL RECOGNITION
=====================================

Your name will be displayed as: {{display_name}}
{{founders_wall_message}}
{{/if}}

=====================================
NEXT STEPS
=====================================

• Keep this email for your records - it serves as your official receipt
• Benefits will be available once The Dink House opens
• Watch your email for facility updates and opening announcements
• Questions? Reply to this email or call us at (254) 123-4567

Visit us at: {{site_url}}

Your support means the world to us. Together, we''re creating something special for the pickleball community in Bell County!

With gratitude,
The Dink House Team

--
The Dink House - Where Pickleball Lives
Questions? Contact us at support@thedinkhouse.com or (254) 123-4567

This is a receipt for your contribution. Please keep for your records.
The Dink House is a project of [Organization Name]. Contributions may be tax-deductible - consult your tax advisor.',
    'crowdfunding',
    '["first_name", "amount", "tier_name", "contribution_date", "contribution_id", "payment_method", "stripe_charge_id", "benefits_html", "benefits_text", "on_founders_wall", "display_name", "founders_wall_message", "site_url"]'::jsonb
)
ON CONFLICT (template_key) DO UPDATE SET
    subject = EXCLUDED.subject,
    html_body = EXCLUDED.html_body,
    text_body = EXCLUDED.text_body,
    variables = EXCLUDED.variables,
    updated_at = CURRENT_TIMESTAMP;

-- Function to log emails
CREATE OR REPLACE FUNCTION system.log_email(
    p_template_key VARCHAR(100),
    p_to_email TEXT,
    p_from_email TEXT,
    p_subject VARCHAR(255),
    p_status VARCHAR(50),
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO system.email_logs (
        template_key,
        to_email,
        from_email,
        subject,
        status,
        metadata,
        sent_at
    ) VALUES (
        p_template_key,
        p_to_email,
        p_from_email,
        p_subject,
        p_status,
        p_metadata,
        CASE WHEN p_status = 'sent' THEN CURRENT_TIMESTAMP ELSE NULL END
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
-- Note: Supabase Cloud uses different role names (authenticator, authenticated, service_role, etc.)
-- Adjust these grants based on your Supabase project's role configuration if needed
-- GRANT USAGE ON SCHEMA system TO authenticated, service_role;
-- GRANT SELECT ON system.email_templates TO authenticated, service_role;
-- GRANT ALL ON system.email_logs TO service_role;
-- GRANT EXECUTE ON FUNCTION system.log_email TO authenticated, service_role;