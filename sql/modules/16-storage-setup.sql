-- ============================================================================
-- STORAGE SETUP MODULE
-- Creates storage buckets for email assets and other media
-- ============================================================================

-- Note: This SQL creates the storage policies.
-- The actual bucket creation needs to be done via Supabase dashboard or CLI

-- Create storage schema if not exists
CREATE SCHEMA IF NOT EXISTS storage;

-- Storage bucket policies for email-assets
DO $$
BEGIN
    -- Check if storage.buckets table exists (Supabase environment)
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'storage'
        AND table_name = 'buckets'
    ) THEN
        -- Insert email-assets bucket if not exists
        INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
        VALUES (
            'email-assets',
            'email-assets',
            true,  -- Public bucket for email images
            false,
            5242880,  -- 5MB limit
            ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/svg+xml', 'image/webp']
        )
        ON CONFLICT (id) DO NOTHING;

        -- Insert general media bucket if not exists
        INSERT INTO storage.buckets (id, name, public, avif_autodetection, file_size_limit, allowed_mime_types)
        VALUES (
            'media',
            'media',
            true,  -- Public bucket for general media
            false,
            52428800,  -- 50MB limit
            ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/svg+xml', 'image/webp', 'video/mp4', 'video/quicktime', 'application/pdf']
        )
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;

-- Create RLS policies for storage (if in Supabase environment)
DO $$
BEGIN
    -- Check if storage.objects table exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'storage'
        AND table_name = 'objects'
    ) THEN
        -- Drop existing policies if they exist
        DROP POLICY IF EXISTS "Email assets are publicly accessible" ON storage.objects;
        DROP POLICY IF EXISTS "Admins can upload email assets" ON storage.objects;
        DROP POLICY IF EXISTS "Admins can update email assets" ON storage.objects;
        DROP POLICY IF EXISTS "Admins can delete email assets" ON storage.objects;

        -- Public read access for email-assets bucket
        CREATE POLICY "Email assets are publicly accessible"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'email-assets');

        -- Admin upload access for email-assets bucket
        CREATE POLICY "Admins can upload email assets"
        ON storage.objects FOR INSERT
        WITH CHECK (
            bucket_id = 'email-assets'
            AND auth.role() IN ('app_admin', 'app_service')
        );

        -- Admin update access for email-assets bucket
        CREATE POLICY "Admins can update email assets"
        ON storage.objects FOR UPDATE
        USING (
            bucket_id = 'email-assets'
            AND auth.role() IN ('app_admin', 'app_service')
        );

        -- Admin delete access for email-assets bucket
        CREATE POLICY "Admins can delete email assets"
        ON storage.objects FOR DELETE
        USING (
            bucket_id = 'email-assets'
            AND auth.role() IN ('app_admin', 'app_service')
        );
    END IF;
END $$;

-- Create a tracking table for uploaded assets
CREATE TABLE IF NOT EXISTS system.uploaded_assets (
    id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
    bucket_id VARCHAR(255) NOT NULL,
    object_path TEXT NOT NULL,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes BIGINT,
    public_url TEXT,
    metadata JSONB DEFAULT '{}',
    uploaded_by UUID REFERENCES app_auth.admin_users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(bucket_id, object_path)
);

-- Create index for asset lookups
CREATE INDEX uploaded_assets_bucket_path ON system.uploaded_assets(bucket_id, object_path);

-- Function to track uploaded assets
CREATE OR REPLACE FUNCTION system.track_uploaded_asset(
    p_bucket_id VARCHAR(255),
    p_object_path TEXT,
    p_filename VARCHAR(255),
    p_content_type VARCHAR(100),
    p_size_bytes BIGINT,
    p_public_url TEXT,
    p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    v_asset_id UUID;
BEGIN
    INSERT INTO system.uploaded_assets (
        bucket_id,
        object_path,
        filename,
        content_type,
        size_bytes,
        public_url,
        metadata
    ) VALUES (
        p_bucket_id,
        p_object_path,
        p_filename,
        p_content_type,
        p_size_bytes,
        p_public_url,
        p_metadata
    )
    ON CONFLICT (bucket_id, object_path)
    DO UPDATE SET
        filename = EXCLUDED.filename,
        content_type = EXCLUDED.content_type,
        size_bytes = EXCLUDED.size_bytes,
        public_url = EXCLUDED.public_url,
        metadata = EXCLUDED.metadata,
        created_at = CURRENT_TIMESTAMP
    RETURNING id INTO v_asset_id;

    RETURN v_asset_id;
END;
$$ LANGUAGE plpgsql;

-- Insert default logo reference
INSERT INTO system.uploaded_assets (bucket_id, object_path, filename, content_type, public_url, metadata)
VALUES (
    'email-assets',
    'dink-house-logo.png',
    'dink-house-logo.png',
    'image/png',
    '{{SUPABASE_URL}}/storage/v1/object/public/email-assets/dink-house-logo.png',
    '{"description": "The Dink House official logo for emails", "dimensions": "300x100"}'::jsonb
)
ON CONFLICT (bucket_id, object_path) DO NOTHING;