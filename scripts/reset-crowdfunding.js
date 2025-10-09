#!/usr/bin/env node

/**
 * Reset Crowdfunding Data Script
 *
 * This script erases ALL crowdfunding data from both the database and Stripe
 * to allow for fresh testing. Use with caution!
 *
 * Usage:
 *   node scripts/reset-crowdfunding.js [options]
 *
 * Options:
 *   --db-only       Only reset database (skip Stripe)
 *   --stripe-only   Only reset Stripe (skip database)
 *   --dry-run       Show what would be deleted without actually deleting
 *   --yes           Skip confirmation prompt
 *
 * Environment Variables Required:
 *   - STRIPE_SECRET_KEY
 *   - SUPABASE_URL
 *   - SUPABASE_SERVICE_KEY
 */

const path = require('path');
const fs = require('fs');

// Try to load environment variables from multiple files in order of preference
const envFiles = ['.env.local', '.env.cloud', '.env'];
let envLoaded = false;

for (const envFile of envFiles) {
  const envPath = path.resolve(__dirname, '..', envFile);
  if (fs.existsSync(envPath)) {
    require('dotenv').config({ path: envPath });
    console.log(`📄 Loaded environment from: ${envFile}`);
    envLoaded = true;
    break;
  }
}

if (!envLoaded) {
  console.warn('⚠️  No .env file found, using process environment variables');
}

const { createClient } = require('@supabase/supabase-js');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const readline = require('readline');

// ============================================================================
// CONFIGURATION
// ============================================================================

const args = process.argv.slice(2);
const options = {
  dbOnly: args.includes('--db-only'),
  stripeOnly: args.includes('--stripe-only'),
  dryRun: args.includes('--dry-run'),
  skipConfirmation: args.includes('--yes')
};

// Validate environment
if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_KEY) {
  console.error('❌ Error: Missing Supabase credentials in environment');
  console.error('Required: SUPABASE_URL, SUPABASE_SERVICE_KEY');
  process.exit(1);
}

// Check if Stripe key is valid (not a placeholder)
const isValidStripeKey = process.env.STRIPE_SECRET_KEY &&
  process.env.STRIPE_SECRET_KEY.startsWith('sk_') &&
  !process.env.STRIPE_SECRET_KEY.includes('your_') &&
  !process.env.STRIPE_SECRET_KEY.includes('_here');

if (!isValidStripeKey && !options.dbOnly) {
  console.warn('⚠️  Warning: STRIPE_SECRET_KEY appears to be a placeholder');
  console.warn('Stripe cleanup will be skipped. Use a valid key or --db-only flag');
  options.dbOnly = true; // Automatically skip Stripe
}

// Initialize Supabase client with service role
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_KEY,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  }
);

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Prompt user for confirmation
 */
function confirm(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    rl.question(question + ' (yes/no): ', (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === 'yes' || answer.toLowerCase() === 'y');
    });
  });
}

/**
 * Log with emoji for better readability
 */
function log(emoji, message, data = null) {
  console.log(`${emoji} ${message}`);
  if (data && options.dryRun) {
    console.log('   ', data);
  }
}

// ============================================================================
// STRIPE CLEANUP
// ============================================================================

async function resetStripe() {
  if (options.dbOnly) {
    log('⏭️', 'Skipping Stripe cleanup (--db-only flag)');
    return;
  }

  log('🔍', 'Scanning Stripe for crowdfunding data...');

  const deletedItems = {
    customers: 0,
    paymentIntents: 0,
    checkoutSessions: 0,
    prices: 0,
    products: 0
  };

  try {
    // 1. Delete Customers (with metadata tag)
    log('👥', 'Fetching Stripe customers...');
    const customers = await stripe.customers.list({
      limit: 100,
      expand: ['data.subscriptions']
    });

    for (const customer of customers.data) {
      // Delete ALL customers during reset (not just crowdfunding-tagged ones)
      if (options.dryRun) {
        log('👤', `[DRY RUN] Would delete customer: ${customer.email} (${customer.id})`);
      } else {
        await stripe.customers.del(customer.id);
        log('✅', `Deleted customer: ${customer.email}`);
      }
      deletedItems.customers++;
    }

    // 2. Delete Payment Intents (recent ones)
    log('💳', 'Fetching payment intents...');
    const paymentIntents = await stripe.paymentIntents.list({
      limit: 100
    });

    for (const pi of paymentIntents.data) {
      if (pi.metadata?.source === 'crowdfunding' || pi.status === 'succeeded') {
        if (options.dryRun) {
          log('💰', `[DRY RUN] Would cancel/delete payment intent: ${pi.id} (${pi.amount / 100})`);
        } else {
          if (pi.status === 'requires_payment_method' || pi.status === 'requires_confirmation') {
            await stripe.paymentIntents.cancel(pi.id);
            log('✅', `Cancelled payment intent: ${pi.id}`);
          }
        }
        deletedItems.paymentIntents++;
      }
    }

    // 3. Delete Checkout Sessions (cannot be deleted, just expire)
    log('🛒', 'Fetching checkout sessions...');
    const sessions = await stripe.checkout.sessions.list({
      limit: 100
    });

    for (const session of sessions.data) {
      if (session.metadata?.source === 'crowdfunding') {
        if (options.dryRun) {
          log('🔗', `[DRY RUN] Would expire session: ${session.id}`);
        } else {
          if (session.status === 'open') {
            await stripe.checkout.sessions.expire(session.id);
            log('✅', `Expired checkout session: ${session.id}`);
          }
        }
        deletedItems.checkoutSessions++;
      }
    }

    // 4. Delete Prices
    log('💵', 'Fetching prices...');
    const prices = await stripe.prices.list({
      limit: 100
    });

    for (const price of prices.data) {
      if (price.metadata?.source === 'crowdfunding' || price.product?.toString().includes('prod_')) {
        if (options.dryRun) {
          log('💲', `[DRY RUN] Would archive price: ${price.id} (${price.unit_amount / 100})`);
        } else {
          // Prices can't be deleted, only archived
          await stripe.prices.update(price.id, { active: false });
          log('✅', `Archived price: ${price.id}`);
        }
        deletedItems.prices++;
      }
    }

    // 5. Delete Products
    log('📦', 'Fetching products...');
    const products = await stripe.products.list({
      limit: 100
    });

    for (const product of products.data) {
      if (product.metadata?.source === 'crowdfunding' || product.name?.includes('Crowdfunding')) {
        if (options.dryRun) {
          log('📦', `[DRY RUN] Would delete product: ${product.name} (${product.id})`);
        } else {
          await stripe.products.del(product.id);
          log('✅', `Deleted product: ${product.name}`);
        }
        deletedItems.products++;
      }
    }

    log('✨', 'Stripe cleanup complete:', deletedItems);

  } catch (error) {
    console.error('❌ Error during Stripe cleanup:', error.message);
    throw error;
  }
}

// ============================================================================
// DATABASE CLEANUP
// ============================================================================

async function resetDatabase() {
  if (options.stripeOnly) {
    log('⏭️', 'Skipping database cleanup (--stripe-only flag)');
    return;
  }

  log('🔍', 'Scanning database for crowdfunding data...');

  const deletedCounts = {
    benefits: 0,
    courtSponsors: 0,
    foundersWall: 0,
    contributions: 0,
    backers: 0
  };

  try {
    // Delete in order of foreign key dependencies (child -> parent)

    // 1. Delete backer_benefits
    log('🎁', 'Deleting backer benefits...');
    if (options.dryRun) {
      const { count } = await supabase
        .schema('crowdfunding')
        .from('backer_benefits')
        .select('*', { count: 'exact', head: true });
      log('📊', `[DRY RUN] Would delete ${count} backer benefits`);
      deletedCounts.benefits = count || 0;
    } else {
      const { error, count } = await supabase
        .schema('crowdfunding')
        .from('backer_benefits')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000'); // Delete all

      if (error) throw error;
      deletedCounts.benefits = count || 0;
      log('✅', `Deleted ${count} backer benefits`);
    }

    // 2. Delete court_sponsors
    log('🏆', 'Deleting court sponsors...');
    if (options.dryRun) {
      const { count } = await supabase
        .schema('crowdfunding')
        .from('court_sponsors')
        .select('*', { count: 'exact', head: true });
      log('📊', `[DRY RUN] Would delete ${count} court sponsors`);
      deletedCounts.courtSponsors = count || 0;
    } else {
      const { error, count } = await supabase
        .schema('crowdfunding')
        .from('court_sponsors')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000');

      if (error) throw error;
      deletedCounts.courtSponsors = count || 0;
      log('✅', `Deleted ${count} court sponsors`);
    }

    // 3. Delete founders_wall
    log('🧱', 'Deleting founders wall entries...');
    if (options.dryRun) {
      const { count } = await supabase
        .schema('crowdfunding')
        .from('founders_wall')
        .select('*', { count: 'exact', head: true });
      log('📊', `[DRY RUN] Would delete ${count} founders wall entries`);
      deletedCounts.foundersWall = count || 0;
    } else {
      const { error, count } = await supabase
        .schema('crowdfunding')
        .from('founders_wall')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000');

      if (error) throw error;
      deletedCounts.foundersWall = count || 0;
      log('✅', `Deleted ${count} founders wall entries`);
    }

    // 4. Delete contributions
    log('💰', 'Deleting contributions...');
    if (options.dryRun) {
      const { count } = await supabase
        .schema('crowdfunding')
        .from('contributions')
        .select('*', { count: 'exact', head: true });
      log('📊', `[DRY RUN] Would delete ${count} contributions`);
      deletedCounts.contributions = count || 0;
    } else {
      const { error, count } = await supabase
        .schema('crowdfunding')
        .from('contributions')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000');

      if (error) throw error;
      deletedCounts.contributions = count || 0;
      log('✅', `Deleted ${count} contributions`);
    }

    // 5. Delete backers
    log('👥', 'Deleting backers...');
    if (options.dryRun) {
      const { count } = await supabase
        .schema('crowdfunding')
        .from('backers')
        .select('*', { count: 'exact', head: true });
      log('📊', `[DRY RUN] Would delete ${count} backers`);
      deletedCounts.backers = count || 0;
    } else {
      const { error, count } = await supabase
        .schema('crowdfunding')
        .from('backers')
        .delete()
        .neq('id', '00000000-0000-0000-0000-000000000000');

      if (error) throw error;
      deletedCounts.backers = count || 0;
      log('✅', `Deleted ${count} backers`);
    }

    // 6. Reset campaign totals (don't delete campaigns/tiers, just reset counters)
    log('📊', 'Resetting campaign totals...');
    if (!options.dryRun) {
      const { error: campaignError } = await supabase
        .schema('crowdfunding')
        .from('campaign_types')
        .update({
          current_amount: 0,
          backer_count: 0,
          updated_at: new Date().toISOString()
        })
        .neq('id', '00000000-0000-0000-0000-000000000000');

      if (campaignError) throw campaignError;

      const { error: tierError } = await supabase
        .schema('crowdfunding')
        .from('contribution_tiers')
        .update({
          current_backers: 0,
          updated_at: new Date().toISOString()
        })
        .neq('id', '00000000-0000-0000-0000-000000000000');

      if (tierError) throw tierError;

      log('✅', 'Reset campaign and tier counters');
    } else {
      log('📊', '[DRY RUN] Would reset campaign and tier counters');
    }

    log('✨', 'Database cleanup complete:', deletedCounts);

  } catch (error) {
    console.error('❌ Error during database cleanup:', error.message);
    throw error;
  }
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

async function main() {
  console.log('\n🚨 CROWDFUNDING DATA RESET UTILITY 🚨\n');

  if (options.dryRun) {
    console.log('🔍 DRY RUN MODE - No data will be deleted\n');
  }

  // Show what will be reset
  const scope = options.dbOnly ? 'DATABASE ONLY'
    : options.stripeOnly ? 'STRIPE ONLY'
    : 'DATABASE + STRIPE';

  console.log(`Scope: ${scope}`);
  console.log('This will delete:');
  if (!options.stripeOnly) {
    console.log('  📊 All backer benefits');
    console.log('  🏆 All court sponsors');
    console.log('  🧱 All founders wall entries');
    console.log('  💰 All contributions');
    console.log('  👥 All backers');
    console.log('  🔄 Reset campaign/tier counters');
  }
  if (!options.dbOnly) {
    console.log('  💳 All Stripe customers (tagged with crowdfunding)');
    console.log('  💰 All payment intents');
    console.log('  🛒 All checkout sessions');
    console.log('  💵 All prices (archived)');
    console.log('  📦 All products');
  }
  console.log('');

  // Confirmation
  if (!options.skipConfirmation && !options.dryRun) {
    const confirmed = await confirm('⚠️  Are you sure you want to proceed? This CANNOT be undone!');
    if (!confirmed) {
      console.log('❌ Cancelled by user');
      process.exit(0);
    }
    console.log('');
  }

  // Execute cleanup
  try {
    const startTime = Date.now();

    // Run in sequence to avoid race conditions
    await resetDatabase();
    await resetStripe();

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);

    console.log('');
    console.log('═══════════════════════════════════════');
    if (options.dryRun) {
      console.log('✨ DRY RUN COMPLETE');
      console.log('No data was actually deleted');
    } else {
      console.log('✨ RESET COMPLETE');
      console.log('All crowdfunding data has been erased');
    }
    console.log(`⏱️  Duration: ${duration}s`);
    console.log('═══════════════════════════════════════');
    console.log('');

  } catch (error) {
    console.error('');
    console.error('═══════════════════════════════════════');
    console.error('❌ RESET FAILED');
    console.error('Error:', error.message);
    console.error('═══════════════════════════════════════');
    console.error('');
    process.exit(1);
  }
}

// Run the script
main().catch(console.error);
