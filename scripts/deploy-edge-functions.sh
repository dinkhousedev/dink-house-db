#!/bin/bash

# Deploy Edge Functions to Supabase Cloud
# This script deploys your Edge Functions using the Supabase CLI

set -e

# Configuration
PROJECT_REF="wchxzbuuwssrnaxshseu"
FUNCTIONS_DIR="./api/functions"

echo "==========================================="
echo "Supabase Edge Functions Deployment"
echo "==========================================="
echo ""
echo "Project Reference: ${PROJECT_REF}"
echo "Functions Directory: ${FUNCTIONS_DIR}"
echo ""

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "Error: Supabase CLI is not installed."
    echo ""
    echo "To install Supabase CLI:"
    echo "  macOS: brew install supabase/tap/supabase"
    echo "  npm: npm install -g supabase"
    echo ""
    echo "For other platforms, visit: https://supabase.com/docs/guides/cli"
    exit 1
fi

# Check if functions directory exists
if [ ! -d "${FUNCTIONS_DIR}" ]; then
    echo "Error: Functions directory not found at ${FUNCTIONS_DIR}"
    exit 1
fi

# Initialize Supabase project (if not already initialized)
if [ ! -f "supabase/.gitignore" ]; then
    echo "Initializing Supabase project..."
    supabase init
fi

# Link to cloud project
echo "Linking to Supabase Cloud project..."
supabase link --project-ref "${PROJECT_REF}"

# Function to deploy a single Edge Function
deploy_function() {
    local function_name=$1
    local function_path="${FUNCTIONS_DIR}/${function_name}"

    if [ -d "${function_path}" ]; then
        echo "Deploying function: ${function_name}..."

        # Check if the function has an index.ts file
        if [ -f "${function_path}/index.ts" ]; then
            supabase functions deploy "${function_name}" \
                --project-ref "${PROJECT_REF}" \
                --no-verify-jwt

            if [ $? -eq 0 ]; then
                echo "✓ Function '${function_name}' deployed successfully"
            else
                echo "✗ Failed to deploy function '${function_name}'"
                return 1
            fi
        else
            echo "⚠ Warning: No index.ts found for function '${function_name}'"
        fi
    else
        echo "⚠ Warning: Function directory '${function_name}' not found"
    fi
}

# Deploy all functions
echo ""
echo "Deploying Edge Functions..."
echo "------------------------"

# List all functions in the directory
for function_dir in ${FUNCTIONS_DIR}/*/; do
    if [ -d "$function_dir" ]; then
        function_name=$(basename "$function_dir")
        deploy_function "$function_name"
    fi
done

# Set function secrets/environment variables
echo ""
echo "Setting function environment variables..."

# Load environment variables from .env.cloud
if [ -f ".env.cloud" ]; then
    echo "Loading environment variables from .env.cloud..."

    # Set secrets for Edge Functions
    supabase secrets set \
        --project-ref "${PROJECT_REF}" \
        SUPABASE_URL="${SUPABASE_URL}" \
        SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
        SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_KEY}"

    echo "✓ Environment variables set"
else
    echo "⚠ Warning: .env.cloud not found. Please set environment variables manually."
fi

# List deployed functions
echo ""
echo "Listing deployed functions..."
supabase functions list --project-ref "${PROJECT_REF}"

echo ""
echo "==========================================="
echo "Edge Functions deployment completed!"
echo "==========================================="
echo ""
echo "Your Edge Functions are now available at:"
echo "  https://${PROJECT_REF}.supabase.co/functions/v1/{function_name}"
echo ""
echo "To test a function:"
echo "  curl -H \"Authorization: Bearer \${SUPABASE_ANON_KEY}\" \\"
echo "       https://${PROJECT_REF}.supabase.co/functions/v1/{function_name}"
echo ""
echo "To view logs:"
echo "  supabase functions logs {function_name} --project-ref ${PROJECT_REF}"