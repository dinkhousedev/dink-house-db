-- ============================================================================
-- SEED DATA: Sample Data
-- Sample contacts, subscribers, and campaigns for testing
-- ============================================================================

-- Set search path for all schemas used
SET search_path TO contact, launch, auth, system, content, public;

-- Insert contact forms
INSERT INTO contact.contact_forms (name, slug, description, fields, email_recipients, success_message, is_active)
VALUES
    (
        'General Contact Form',
        'general-contact',
        'Main contact form for general inquiries',
        '[
            {"name": "first_name", "type": "text", "required": true, "label": "First Name"},
            {"name": "last_name", "type": "text", "required": true, "label": "Last Name"},
            {"name": "email", "type": "email", "required": true, "label": "Email"},
            {"name": "phone", "type": "tel", "required": false, "label": "Phone"},
            {"name": "company", "type": "text", "required": false, "label": "Company"},
            {"name": "subject", "type": "text", "required": true, "label": "Subject"},
            {"name": "message", "type": "textarea", "required": true, "label": "Message"}
        ]'::jsonb,
        ARRAY['contact@dinkhouse.com', 'admin@dinkhouse.com'],
        'Thank you for contacting us. We will respond within 24-48 hours.',
        true
    ),
    (
        'Support Request Form',
        'support-request',
        'Technical support request form',
        '[
            {"name": "first_name", "type": "text", "required": true, "label": "First Name"},
            {"name": "last_name", "type": "text", "required": true, "label": "Last Name"},
            {"name": "email", "type": "email", "required": true, "label": "Email"},
            {"name": "issue_type", "type": "select", "required": true, "label": "Issue Type", "options": ["Bug", "Feature Request", "Question", "Other"]},
            {"name": "priority", "type": "select", "required": true, "label": "Priority", "options": ["Low", "Medium", "High", "Urgent"]},
            {"name": "description", "type": "textarea", "required": true, "label": "Description"}
        ]'::jsonb,
        ARRAY['support@dinkhouse.com'],
        'Your support request has been received. Ticket number: #{{ticket_id}}',
        true
    );

-- Insert sample contact inquiries
INSERT INTO contact.contact_inquiries (form_id, first_name, last_name, email, phone, company, subject, message, source, status, priority)
SELECT
    f.id,
    'Michael',
    'Johnson',
    'michael.johnson@techcorp.com',
    '+1 (555) 234-5678',
    'TechCorp Inc.',
    'Partnership Opportunity',
    'Hi, I represent TechCorp and we are interested in exploring partnership opportunities with your company. Could we schedule a call to discuss?',
    'website',
    'new',
    'high'
FROM contact.contact_forms f WHERE f.slug = 'general-contact';

INSERT INTO contact.contact_inquiries (form_id, first_name, last_name, email, phone, company, subject, message, source, status, priority, assigned_to)
SELECT
    f.id,
    'Sarah',
    'Williams',
    'sarah.w@startup.io',
    '+1 (555) 345-6789',
    'Startup.io',
    'Product Demo Request',
    'We would like to schedule a demo of your product for our team. We have 10-15 team members who would be interested.',
    'website',
    'in_progress',
    'medium',
    u.id
FROM contact.contact_forms f, auth.users u
WHERE f.slug = 'general-contact' AND u.username = 'john.doe';

INSERT INTO contact.contact_inquiries (form_id, first_name, last_name, email, subject, message, source, status, priority)
SELECT
    f.id,
    'David',
    'Brown',
    'david.brown@email.com',
    'Question about pricing',
    'Can you provide more information about your enterprise pricing plans?',
    'website',
    'responded',
    'low'
FROM contact.contact_forms f WHERE f.slug = 'general-contact';

-- Insert launch campaigns
INSERT INTO launch.launch_campaigns (name, slug, description, campaign_type, launch_date, status, created_by)
SELECT
    'Product Launch 2024',
    'product-launch-2024',
    'Official launch of our new product line with enhanced features and capabilities.',
    'product_launch',
    CURRENT_TIMESTAMP + INTERVAL '30 days',
    'scheduled',
    id
FROM auth.users WHERE username = 'admin';

INSERT INTO launch.launch_campaigns (name, slug, description, campaign_type, launch_date, status, created_by)
SELECT
    'Summer Feature Release',
    'summer-feature-release',
    'Announcing new features for the summer season including improved performance and UI updates.',
    'feature_release',
    CURRENT_TIMESTAMP + INTERVAL '60 days',
    'draft',
    id
FROM auth.users WHERE username = 'editor';

INSERT INTO launch.launch_campaigns (name, slug, description, campaign_type, status, created_by)
SELECT
    'Monthly Newsletter - January',
    'newsletter-january',
    'Our monthly newsletter with updates, tips, and industry insights.',
    'newsletter',
    'completed',
    id
FROM auth.users WHERE username = 'admin';

-- Insert launch subscribers
INSERT INTO launch.launch_subscribers (email, first_name, last_name, company, interests, source, is_active, verified_at)
VALUES
    ('subscriber1@example.com', 'Alice', 'Anderson', 'Anderson Tech', ARRAY['product_updates', 'tech_news'], 'website', true, CURRENT_TIMESTAMP),
    ('subscriber2@example.com', 'Bob', 'Baker', 'Baker Industries', ARRAY['product_updates', 'events'], 'website', true, CURRENT_TIMESTAMP),
    ('subscriber3@example.com', 'Carol', 'Clark', 'Clark Solutions', ARRAY['tech_news', 'tutorials'], 'referral', true, CURRENT_TIMESTAMP),
    ('subscriber4@example.com', 'Daniel', 'Davis', 'Davis Corp', ARRAY['product_updates'], 'social_media', true, CURRENT_TIMESTAMP),
    ('subscriber5@example.com', 'Emma', 'Evans', NULL, ARRAY['events', 'tech_news'], 'website', true, CURRENT_TIMESTAMP),
    ('subscriber6@example.com', 'Frank', 'Fisher', 'Fisher LLC', ARRAY['product_updates', 'tutorials'], 'website', true, CURRENT_TIMESTAMP),
    ('inactive@example.com', 'Inactive', 'User', NULL, ARRAY['product_updates'], 'website', false, NULL),
    ('bounced@example.com', 'Bounced', 'Email', 'Failed Company', ARRAY['product_updates'], 'website', true, CURRENT_TIMESTAMP);

-- Update bounce count for demonstration
UPDATE launch.launch_subscribers SET bounce_count = 3 WHERE email = 'bounced@example.com';

-- Link subscribers to campaigns
INSERT INTO launch.launch_campaign_subscribers (campaign_id, subscriber_id)
SELECT c.id, s.id
FROM launch.launch_campaigns c
CROSS JOIN launch.launch_subscribers s
WHERE c.slug = 'product-launch-2024' AND s.is_active = true;

-- Insert sample notifications
INSERT INTO launch.launch_notifications (campaign_id, subscriber_id, notification_type, subject, content, status, sent_at, delivered_at, opened_at)
SELECT
    c.id,
    s.id,
    'email',
    'Monthly Newsletter - January',
    'Check out our latest updates and insights...',
    'delivered',
    CURRENT_TIMESTAMP - INTERVAL '7 days',
    CURRENT_TIMESTAMP - INTERVAL '7 days' + INTERVAL '1 hour',
    CURRENT_TIMESTAMP - INTERVAL '6 days'
FROM launch.launch_campaigns c, launch.launch_subscribers s
WHERE c.slug = 'newsletter-january' AND s.email IN ('subscriber1@example.com', 'subscriber2@example.com', 'subscriber3@example.com');

-- Insert sample activity logs
INSERT INTO system.activity_logs (user_id, action, entity_type, entity_id, details)
SELECT
    id,
    'login',
    'auth.users',
    id,
    '{"ip": "192.168.1.100", "browser": "Chrome 120.0"}'::jsonb
FROM auth.users WHERE username = 'admin';

INSERT INTO system.activity_logs (user_id, action, entity_type, entity_id, details)
SELECT
    u.id,
    'create',
    'content.pages',
    p.id,
    '{"title": "Welcome to Dink House"}'::jsonb
FROM auth.users u, content.pages p
WHERE u.username = 'admin' AND p.slug = 'welcome';

-- Insert sample system jobs
INSERT INTO system.system_jobs (job_type, job_name, payload, status, priority, scheduled_at, completed_at, created_by)
SELECT
    'email_campaign',
    'Send Product Launch Emails',
    '{"campaign_id": "' || c.id || '", "batch_size": 100}'::jsonb,
    'completed',
    8,
    CURRENT_TIMESTAMP - INTERVAL '1 day',
    CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '30 minutes',
    u.id
FROM launch.launch_campaigns c, auth.users u
WHERE c.slug = 'newsletter-january' AND u.username = 'admin';

INSERT INTO system.system_jobs (job_type, job_name, payload, status, priority, scheduled_at, created_by)
SELECT
    'cleanup',
    'Clean Expired Sessions',
    '{}'::jsonb,
    'pending',
    3,
    CURRENT_TIMESTAMP + INTERVAL '1 hour',
    id
FROM auth.users WHERE username = 'admin';

-- Calculate engagement scores for subscribers
UPDATE launch.launch_subscribers
SET engagement_score = (
    CASE
        WHEN email = 'subscriber1@example.com' THEN 85.5
        WHEN email = 'subscriber2@example.com' THEN 72.3
        WHEN email = 'subscriber3@example.com' THEN 65.0
        WHEN email = 'subscriber4@example.com' THEN 45.8
        WHEN email = 'subscriber5@example.com' THEN 30.0
        ELSE 0
    END
)
WHERE email IN ('subscriber1@example.com', 'subscriber2@example.com', 'subscriber3@example.com', 'subscriber4@example.com', 'subscriber5@example.com');