// Main Edge Function Entry Point
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { url, method } = req
  const path = new URL(url).pathname

  // CORS headers
  const headers = new Headers({
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  })

  // Handle CORS preflight
  if (method === "OPTIONS") {
    return new Response("ok", { headers })
  }

  try {
    return new Response(
      JSON.stringify({
        message: "Dink House Edge Functions",
        path,
        method,
        timestamp: new Date().toISOString()
      }),
      {
        headers: {
          ...Object.fromEntries(headers),
          "Content-Type": "application/json"
        },
        status: 200
      }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: {
          ...Object.fromEntries(headers),
          "Content-Type": "application/json"
        },
        status: 500
      }
    )
  }
})