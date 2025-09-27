-- ============================================================================
-- SEED DATA: Content Management
-- Sample categories, pages, and media
-- ============================================================================

-- Set search path for content management
SET search_path TO content, auth, public;

-- Insert content categories
INSERT INTO content.categories (name, slug, description, sort_order, is_active)
VALUES
    ('Blog', 'blog', 'Blog posts and articles', 1, true),
    ('Products', 'products', 'Product pages and descriptions', 2, true),
    ('Services', 'services', 'Service offerings', 3, true),
    ('Documentation', 'docs', 'Technical documentation', 4, true),
    ('News', 'news', 'Company news and updates', 5, true);

-- Insert sample pages
INSERT INTO content.pages (title, slug, content, excerpt, meta_title, meta_description, category_id, status, author_id, published_at)
SELECT
    'Welcome to Dink House',
    'welcome',
    '<h1>Welcome to Dink House</h1><p>This is your new content management system. Start creating amazing content today!</p>',
    'Welcome to our platform. Discover what we can do for you.',
    'Welcome to Dink House - Your CMS Solution',
    'Discover Dink House, a powerful content management system for your business needs.',
    c.id,
    'published',
    u.id,
    CURRENT_TIMESTAMP
FROM content.categories c, app_auth.admin_users u
WHERE c.slug = 'blog' AND u.username = 'admin';

INSERT INTO content.pages (title, slug, content, excerpt, meta_title, meta_description, category_id, status, author_id, published_at)
SELECT
    'Getting Started Guide',
    'getting-started',
    '<h2>Getting Started</h2><p>Follow these steps to get up and running quickly...</p>',
    'Learn how to get started with our platform in just a few minutes.',
    'Getting Started Guide - Dink House',
    'Complete guide to getting started with Dink House CMS.',
    c.id,
    'published',
    u.id,
    CURRENT_TIMESTAMP
FROM content.categories c, app_auth.admin_users u
WHERE c.slug = 'docs' AND u.username = 'editor';

INSERT INTO content.pages (title, slug, content, excerpt, category_id, status, author_id)
SELECT
    'Upcoming Features',
    'upcoming-features',
    '<h2>Exciting Features Coming Soon</h2><p>We are working on amazing new features...</p>',
    'Preview of upcoming features and improvements.',
    c.id,
    'draft',
    u.id
FROM content.categories c, app_auth.admin_users u
WHERE c.slug = 'news' AND u.username = 'editor';