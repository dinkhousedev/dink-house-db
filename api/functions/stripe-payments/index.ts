import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@14.10.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") || "", {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
const supabase = createClient(supabaseUrl, supabaseServiceKey);

const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") || "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, stripe-signature",
};

interface BenefitDetail {
  type: string;
  details?: Record<string, unknown>;
  lifetime?: boolean;
  expiresAt?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const signature = req.headers.get("stripe-signature");

    if (!signature) {
      console.error("Missing stripe-signature header");
      return new Response(
        JSON.stringify({ error: "Missing stripe-signature header" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get raw body for signature verification
    const body = await req.text();

    // Verify webhook signature
    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(body, signature, webhookSecret);
    } catch (err) {
      console.error("Webhook signature verification failed:", err);
      return new Response(
        JSON.stringify({ error: `Webhook signature verification failed: ${err.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Processing event: ${event.type}`);

    // Handle different event types
    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session;
        await handleCheckoutCompleted(session);
        break;
      }

      case "payment_intent.succeeded": {
        const paymentIntent = event.data.object as Stripe.PaymentIntent;
        await handlePaymentSucceeded(paymentIntent);
        break;
      }

      case "payment_intent.payment_failed": {
        const paymentIntent = event.data.object as Stripe.PaymentIntent;
        await handlePaymentFailed(paymentIntent);
        break;
      }

      case "charge.refunded": {
        const charge = event.data.object as Stripe.Charge;
        await handleChargeRefunded(charge);
        break;
      }

      default:
        console.log(`Unhandled event type: ${event.type}`);
    }

    return new Response(
      JSON.stringify({ received: true }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error processing webhook:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  console.log("Processing checkout.session.completed", session.id);

  const contributionId = session.metadata?.contribution_id;
  const backerId = session.metadata?.backer_id;
  const tierId = session.metadata?.tier_id;

  if (!contributionId) {
    console.error("Missing contribution_id in session metadata");
    return;
  }

  try {
    // Update contribution status
    const { error: updateError } = await supabase
      .from("contributions")
      .update({
        status: "completed",
        stripe_payment_intent_id: session.payment_intent as string,
        stripe_checkout_session_id: session.id,
        completed_at: new Date().toISOString(),
        payment_method: session.payment_method_types?.[0] || "card",
      })
      .eq("id", contributionId)
      .select()
      .single();

    if (updateError) {
      console.error("Error updating contribution:", updateError);
      throw updateError;
    }

    console.log("Contribution updated successfully:", contributionId);

    // Get tier details to create benefits
    if (tierId) {
      const { data: tier, error: tierError } = await supabase
        .from("contribution_tiers")
        .select("benefits")
        .eq("id", tierId)
        .single();

      if (tierError) {
        console.error("Error fetching tier:", tierError);
      } else if (tier?.benefits && Array.isArray(tier.benefits)) {
        console.log("Creating benefits for tier:", tierId);

        // Create backer benefits
        for (const benefit of tier.benefits as BenefitDetail[]) {
          const { error: benefitError } = await supabase
            .from("backer_benefits")
            .insert({
              backer_id: backerId,
              contribution_id: contributionId,
              benefit_type: benefit.type,
              benefit_details: benefit.details || {},
              expires_at: benefit.lifetime ? null : benefit.expiresAt,
            });

          if (benefitError) {
            console.error("Error creating benefit:", benefitError);
          }
        }
      }
    }

    // Check if this qualifies for court sponsorship ($1000+)
    const { data: contribution } = await supabase
      .from("contributions")
      .select("amount")
      .eq("id", contributionId)
      .single();

    if (contribution && contribution.amount >= 1000) {
      const { data: backer } = await supabase
        .from("backers")
        .select("first_name, last_initial")
        .eq("id", backerId)
        .single();

      if (backer) {
        await supabase.from("court_sponsors").insert({
          backer_id: backerId,
          contribution_id: contributionId,
          sponsor_name: `${backer.first_name} ${backer.last_initial}.`,
          sponsor_type: "individual",
          sponsorship_start: new Date().toISOString().split("T")[0],
        });

        console.log("Created court sponsor entry");
      }
    }

    console.log("Checkout completed processing finished");
  } catch (error) {
    console.error("Error in handleCheckoutCompleted:", error);
    throw error;
  }
}

async function handlePaymentSucceeded(paymentIntent: Stripe.PaymentIntent) {
  console.log("Processing payment_intent.succeeded", paymentIntent.id);

  // Update contribution if exists
  const { error } = await supabase
    .from("contributions")
    .update({
      status: "completed",
      stripe_charge_id: paymentIntent.latest_charge as string,
    })
    .eq("stripe_payment_intent_id", paymentIntent.id);

  if (error) {
    console.error("Error updating contribution on payment success:", error);
  }
}

async function handlePaymentFailed(paymentIntent: Stripe.PaymentIntent) {
  console.log("Processing payment_intent.payment_failed", paymentIntent.id);

  const { error } = await supabase
    .from("contributions")
    .update({
      status: "failed",
    })
    .eq("stripe_payment_intent_id", paymentIntent.id);

  if (error) {
    console.error("Error updating contribution on payment failure:", error);
  }
}

async function handleChargeRefunded(charge: Stripe.Charge) {
  console.log("Processing charge.refunded", charge.id);

  // Update contribution status
  const { data: contribution, error: fetchError } = await supabase
    .from("contributions")
    .select("id")
    .eq("stripe_charge_id", charge.id)
    .single();

  if (fetchError || !contribution) {
    console.error("Error finding contribution for refund:", fetchError);
    return;
  }

  // Update contribution status
  const { error: updateError } = await supabase
    .from("contributions")
    .update({
      status: "refunded",
      refunded_at: new Date().toISOString(),
    })
    .eq("id", contribution.id);

  if (updateError) {
    console.error("Error updating contribution on refund:", updateError);
    return;
  }

  // Deactivate benefits
  const { error: benefitsError } = await supabase
    .from("backer_benefits")
    .update({
      is_active: false,
    })
    .eq("contribution_id", contribution.id);

  if (benefitsError) {
    console.error("Error deactivating benefits:", benefitsError);
  }

  // Deactivate court sponsor
  const { error: sponsorError } = await supabase
    .from("court_sponsors")
    .update({
      is_active: false,
    })
    .eq("contribution_id", contribution.id);

  if (sponsorError) {
    console.error("Error deactivating court sponsor:", sponsorError);
  }

  console.log("Refund processing completed");
}
