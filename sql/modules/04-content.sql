-- ============================================================================
-- CONTENT MANAGEMENT MODULE
-- Pages, categories, and media management in content schema
-- ============================================================================

-- Switch to content schema
SET search_path TO content, public;

-- Content categories
CREATE TABLE IF NOT EXISTS content.categories (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    parent_id UUID REFERENCES content.categories(id) ON DELETE CASCADE,
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    meta_data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Content pages
CREATE TABLE IF NOT EXISTS content.pages (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    content TEXT,
    excerpt TEXT,
    featured_image VARCHAR(500),
    meta_title VARCHAR(255),
    meta_description TEXT,
    meta_keywords TEXT[],
    category_id UUID REFERENCES content.categories(id) ON DELETE SET NULL,
    status VARCHAR(50) DEFAULT 'draft'
        CHECK (status IN ('draft', 'published', 'scheduled', 'archived')),
    visibility VARCHAR(50) DEFAULT 'public'
        CHECK (visibility IN ('public', 'private', 'password_protected')),
    password_hash VARCHAR(255),
    author_id UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    editor_id UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    published_at TIMESTAMP WITH TIME ZONE,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    views_count INT DEFAULT 0,
    custom_data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Media files
CREATE TABLE IF NOT EXISTS content.media_files (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    filename VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_url VARCHAR(500),
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_extension VARCHAR(20),
    width INT,
    height INT,
    duration INT, -- For video/audio files in seconds
    alt_text VARCHAR(255),
    caption TEXT,
    folder_path VARCHAR(500) DEFAULT '/',
    tags TEXT[],
    metadata JSONB DEFAULT '{}',
    uploaded_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Content revisions for version control
CREATE TABLE IF NOT EXISTS content.revisions (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    page_id UUID NOT NULL REFERENCES content.pages(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT,
    excerpt TEXT,
    meta_data JSONB,
    revision_number INT NOT NULL,
    revision_message TEXT,
    created_by UUID NOT NULL REFERENCES app_auth.admin_users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for content tables
CREATE INDEX idx_categories_slug ON content.categories(slug);
CREATE INDEX idx_categories_parent_id ON content.categories(parent_id);
CREATE INDEX idx_pages_slug ON content.pages(slug);
CREATE INDEX idx_pages_status ON content.pages(status);
CREATE INDEX idx_pages_author_id ON content.pages(author_id);
CREATE INDEX idx_pages_category_id ON content.pages(category_id);
CREATE INDEX idx_pages_published_at ON content.pages(published_at);
CREATE INDEX idx_media_files_mime_type ON content.media_files(mime_type);
CREATE INDEX idx_media_files_uploaded_by ON content.media_files(uploaded_by);
CREATE INDEX idx_media_files_folder_path ON content.media_files(folder_path);
CREATE INDEX idx_revisions_page_id ON content.revisions(page_id);
