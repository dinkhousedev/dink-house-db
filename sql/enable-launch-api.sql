-- Enable launch schema tables in public API
-- This creates views in the public schema that reference launch schema tables

-- Create view for launch_subscribers in public schema
CREATE OR REPLACE VIEW public.launch_subscribers AS
SELECT * FROM launch.launch_subscribers;

-- Grant access to the views
GRANT SELECT, INSERT, UPDATE, DELETE ON public.launch_subscribers TO anon, authenticated, service_role;

-- Enable RLS on the view
ALTER VIEW public.launch_subscribers SET (security_invoker = on);

-- Alternative: You can also expose the launch schema directly
-- Run this in Supabase SQL Editor or via psql:
-- ALTER DATABASE postgres SET "request.header.accept-profile" = 'public, launch';
-- Then reload the PostgREST schema cache by restarting the API
