#!/usr/bin/env node

/**
 * CLI tool for deleting all non-admin player profiles from the Dink House database
 * This tool safely removes player accounts, auth records, and associated Stripe customers
 *
 * DANGER: This is a destructive operation that cannot be undone!
 *
 * Usage:
 *   node api/cli/delete-all-players.js              # Local database, interactive
 *   node api/cli/delete-all-players.js --cloud      # Cloud database, interactive
 *   node api/cli/delete-all-players.js --dry-run    # Preview only
 *   node api/cli/delete-all-players.js --cloud --dry-run  # Preview cloud
 *   node api/cli/delete-all-players.js --force      # Skip confirmation
 */

const path = require('path');
const { Command } = require('commander');
const { Client } = require('pg');
const inquirer = require('inquirer');
const Stripe = require('stripe');

// Initialize commander first to get cloud flag
const program = new Command();

program
  .name('delete-all-players')
  .description('Delete all non-admin player profiles, auth users, and Stripe customers')
  .version('1.0.0')
  .option('--dry-run', 'Preview what will be deleted without actually deleting')
  .option('--force', 'Skip confirmation prompt (use with caution!)')
  .option('--cloud', 'Connect to Supabase cloud database instead of local')
  .parse(process.argv);

const options = program.opts();

// Load appropriate environment file
if (options.cloud) {
  require('dotenv').config({ path: path.join(__dirname, '../../.env.cloud') });
  console.log('☁️  Using CLOUD database configuration\n');
} else {
  require('dotenv').config();
  console.log('💻 Using LOCAL database configuration\n');
}

// Database configuration
function getDatabaseConfig() {
  if (options.cloud && process.env.DATABASE_URL) {
    // Parse DATABASE_URL for cloud connection
    const url = new URL(process.env.DATABASE_URL);
    return {
      host: url.hostname,
      port: parseInt(url.port),
      database: url.pathname.slice(1),
      user: url.username,
      password: url.password,
      ssl: { rejectUnauthorized: false }
    };
  } else {
    // Local database
    return {
      host: process.env.DB_HOST || 'localhost',
      port: process.env.DB_PORT || 9432,
      database: process.env.POSTGRES_DB || 'dink_house',
      user: process.env.POSTGRES_USER || 'postgres',
      password: process.env.POSTGRES_PASSWORD || 'DevPassword123!',
    };
  }
}

const dbConfig = getDatabaseConfig();

// Stripe configuration
const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
const stripe = stripeSecretKey ? new Stripe(stripeSecretKey) : null;

/**
 * Check if stripe_customer_id column exists
 */
async function hasStripeCustomerIdColumn(client) {
  const query = `
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'app_auth'
        AND table_name = 'players'
        AND column_name = 'stripe_customer_id'
    ) as has_column
  `;

  const result = await client.query(query);
  return result.rows[0].has_column;
}

/**
 * Get all player accounts with optional Stripe customer IDs
 */
async function getPlayerAccounts(client, hasStripeColumn) {
  const stripeField = hasStripeColumn ? 'p.stripe_customer_id,' : '';

  // Use LEFT JOIN to get all players, even if user_accounts record is missing or has wrong type
  // This handles orphaned player records
  const query = `
    SELECT
      p.id as player_id,
      p.account_id,
      p.first_name,
      p.last_name,
      ${stripeField}
      COALESCE(u.email, 'no-email@orphaned.record') as email,
      COALESCE(u.user_type::text, 'orphaned') as user_type,
      COALESCE(u.created_at, p.created_at) as created_at
    FROM app_auth.players p
    LEFT JOIN app_auth.user_accounts u ON p.account_id = u.id
    ORDER BY p.created_at DESC
  `;

  const result = await client.query(query);
  return result.rows;
}

/**
 * Get Stripe customer IDs from crowdfunding backers
 */
async function getBackerStripeCustomers(client, playerEmails) {
  if (playerEmails.length === 0) {
    return [];
  }

  const query = `
    SELECT DISTINCT stripe_customer_id
    FROM crowdfunding.backers
    WHERE email = ANY($1)
      AND stripe_customer_id IS NOT NULL
  `;

  try {
    const result = await client.query(query, [playerEmails]);
    return result.rows.map(row => row.stripe_customer_id);
  } catch (error) {
    // crowdfunding schema might not exist
    console.log('  ℹ️  Crowdfunding schema not found, skipping backer Stripe customers');
    return [];
  }
}

/**
 * Count related records that will be deleted via CASCADE
 */
async function getRelatedRecordsCounts(client, accountIds) {
  if (accountIds.length === 0) {
    return { sessions: 0, refreshTokens: 0, apiKeys: 0 };
  }

  const counts = { sessions: 0, refreshTokens: 0, apiKeys: 0 };

  // Try to count sessions (may not exist in cloud)
  try {
    const sessionsQuery = `
      SELECT COUNT(*) as count
      FROM app_auth.sessions
      WHERE account_id = ANY($1)
    `;
    const result = await client.query(sessionsQuery, [accountIds]);
    counts.sessions = parseInt(result.rows[0].count);
  } catch (error) {
    // Table doesn't exist, skip
  }

  // Try to count refresh tokens (may not exist in cloud)
  try {
    const refreshTokensQuery = `
      SELECT COUNT(*) as count
      FROM app_auth.refresh_tokens
      WHERE account_id = ANY($1)
    `;
    const result = await client.query(refreshTokensQuery, [accountIds]);
    counts.refreshTokens = parseInt(result.rows[0].count);
  } catch (error) {
    // Table doesn't exist, skip
  }

  // Try to count API keys (may not exist in cloud)
  try {
    const apiKeysQuery = `
      SELECT COUNT(*) as count
      FROM app_auth.api_keys
      WHERE account_id = ANY($1)
    `;
    const result = await client.query(apiKeysQuery, [accountIds]);
    counts.apiKeys = parseInt(result.rows[0].count);
  } catch (error) {
    // Table doesn't exist, skip
  }

  return counts;
}

/**
 * Delete Stripe customer
 */
async function deleteStripeCustomer(customerId, dryRun = false) {
  if (!stripe) {
    console.warn('⚠️  Stripe not configured - skipping Stripe customer deletion');
    return { success: false, skipped: true };
  }

  if (dryRun) {
    console.log(`  [DRY RUN] Would delete Stripe customer: ${customerId}`);
    return { success: true, dryRun: true };
  }

  try {
    await stripe.customers.del(customerId);
    return { success: true };
  } catch (error) {
    console.error(`  ❌ Error deleting Stripe customer ${customerId}:`, error.message);
    return { success: false, error: error.message };
  }
}

/**
 * Delete all player records and their associated accounts from database
 */
async function deletePlayerAccounts(client, players, tablesExist, dryRun = false) {
  if (players.length === 0) {
    return { playersDeleted: 0, accountsDeleted: 0 };
  }

  if (dryRun) {
    const accountIds = players.map(p => p.account_id).filter(id => id);
    console.log(`  [DRY RUN] Would delete ${players.length} player records`);
    console.log(`  [DRY RUN] Would delete ${accountIds.length} user accounts from database`);
    return { playersDeleted: players.length, accountsDeleted: accountIds.length, dryRun: true };
  }

  // Step 1: Delete player records directly (some may not have associated user_accounts)
  const playerIds = players.map(p => p.player_id);
  const deletePlayersQuery = `
    DELETE FROM app_auth.players
    WHERE id = ANY($1)
    RETURNING id
  `;

  const playersResult = await client.query(deletePlayersQuery, [playerIds]);

  // Step 2: Delete orphaned user_accounts if they exist and aren't referenced by admins/guests
  // Only delete accounts that were associated with players we just deleted
  const accountIds = players.map(p => p.account_id).filter(id => id);
  let accountsDeleted = 0;

  if (accountIds.length > 0) {
    // Build query based on which tables exist (checked before transaction)
    let whereConditions = ['id = ANY($1)'];

    if (tablesExist.adminUsers) {
      whereConditions.push(`NOT EXISTS (
        SELECT 1 FROM app_auth.admin_users WHERE account_id = app_auth.user_accounts.id
      )`);
    }

    if (tablesExist.guestUsers) {
      whereConditions.push(`NOT EXISTS (
        SELECT 1 FROM app_auth.guest_users WHERE account_id = app_auth.user_accounts.id
      )`);
    }

    const deleteAccountsQuery = `
      DELETE FROM app_auth.user_accounts
      WHERE ${whereConditions.join(' AND ')}
      RETURNING id
    `;

    try {
      const accountsResult = await client.query(deleteAccountsQuery, [accountIds]);
      accountsDeleted = accountsResult.rowCount;
    } catch (error) {
      console.log(`  ⚠️  Could not delete user_accounts: ${error.message}`);
    }
  }

  return {
    playersDeleted: playersResult.rowCount,
    accountsDeleted: accountsDeleted
  };
}

/**
 * Main execution function
 */
async function main() {
  console.log('\n🏓 Dink House - Delete All Player Profiles\n');
  console.log('═'.repeat(60));

  const client = new Client(dbConfig);

  try {
    // Connect to database
    await client.connect();
    console.log('✅ Connected to database\n');

    // Check if stripe_customer_id column exists
    const hasStripeColumn = await hasStripeCustomerIdColumn(client);

    // Get all player accounts
    console.log('📊 Fetching player accounts...');
    const players = await getPlayerAccounts(client, hasStripeColumn);

    if (players.length === 0) {
      console.log('\n✨ No player accounts found. Database is clean!\n');
      await client.end();
      return;
    }

    console.log(`\nFound ${players.length} player account(s):\n`);

    // Display player information
    players.forEach((player, index) => {
      console.log(`  ${index + 1}. ${player.first_name} ${player.last_name} (${player.email})`);
      if (hasStripeColumn && player.stripe_customer_id) {
        console.log(`     Stripe Customer: ${player.stripe_customer_id}`);
      }
      console.log(`     Created: ${new Date(player.created_at).toLocaleDateString()}`);
      console.log('');
    });

    // Get related records counts
    const accountIds = players.map(p => p.account_id);
    const relatedCounts = await getRelatedRecordsCounts(client, accountIds);

    console.log('📋 Related records that will be deleted:');
    console.log(`   - Sessions: ${relatedCounts.sessions}`);
    console.log(`   - Refresh Tokens: ${relatedCounts.refreshTokens}`);
    console.log(`   - API Keys: ${relatedCounts.apiKeys}\n`);

    // Collect Stripe customer IDs from multiple sources
    let stripeCustomerIds = [];

    // Source 1: From players table (if column exists)
    if (hasStripeColumn) {
      const playerStripeIds = players
        .filter(p => p.stripe_customer_id)
        .map(p => p.stripe_customer_id);
      stripeCustomerIds.push(...playerStripeIds);
    }

    // Source 2: From crowdfunding backers (if schema exists)
    const playerEmails = players.map(p => p.email);
    const backerStripeIds = await getBackerStripeCustomers(client, playerEmails);
    stripeCustomerIds.push(...backerStripeIds);

    // Remove duplicates
    stripeCustomerIds = [...new Set(stripeCustomerIds)];

    if (stripeCustomerIds.length > 0) {
      console.log(`💳 Stripe customers to delete: ${stripeCustomerIds.length}\n`);
    }

    // Dry run mode
    if (options.dryRun) {
      console.log('═'.repeat(60));
      console.log('\n🔍 DRY RUN MODE - No changes will be made\n');
      console.log('Summary of what would be deleted:');
      console.log(`  - ${players.length} player profiles`);
      console.log(`  - ${players.length} user accounts`);
      console.log(`  - ${relatedCounts.sessions} sessions`);
      console.log(`  - ${relatedCounts.refreshTokens} refresh tokens`);
      console.log(`  - ${relatedCounts.apiKeys} API keys`);
      console.log(`  - ${stripeCustomerIds.length} Stripe customers\n`);
      console.log('═'.repeat(60));
      await client.end();
      return;
    }

    // Confirmation prompt (unless --force flag is used)
    if (!options.force) {
      console.log('═'.repeat(60));
      console.log('\n⚠️  WARNING: This action cannot be undone!\n');

      const answers = await inquirer.prompt([
        {
          type: 'confirm',
          name: 'confirmDelete',
          message: `Are you sure you want to delete ${players.length} player account(s) and all related data?`,
          default: false,
        },
      ]);

      if (!answers.confirmDelete) {
        console.log('\n❌ Operation cancelled by user.\n');
        await client.end();
        return;
      }

      // Double confirmation for safety
      const doubleConfirm = await inquirer.prompt([
        {
          type: 'input',
          name: 'confirmText',
          message: 'Type "DELETE ALL PLAYERS" to confirm:',
        },
      ]);

      if (doubleConfirm.confirmText !== 'DELETE ALL PLAYERS') {
        console.log('\n❌ Confirmation text did not match. Operation cancelled.\n');
        await client.end();
        return;
      }
    }

    console.log('\n🚀 Starting deletion process...\n');
    console.log('═'.repeat(60));

    // Check which tables exist BEFORE transaction (to avoid aborting transaction)
    const tablesExist = {
      adminUsers: false,
      guestUsers: false
    };

    try {
      await client.query('SELECT 1 FROM app_auth.admin_users LIMIT 1');
      tablesExist.adminUsers = true;
    } catch (e) { /* table doesn't exist */ }

    try {
      await client.query('SELECT 1 FROM app_auth.guest_users LIMIT 1');
      tablesExist.guestUsers = true;
    } catch (e) { /* table doesn't exist */ }

    // Begin transaction
    await client.query('BEGIN');

    try {
      // Step 1: Delete Stripe customers
      if (stripeCustomerIds.length > 0) {
        console.log('\n💳 Deleting Stripe customers...');
        let stripeSuccessCount = 0;
        let stripeFailCount = 0;

        for (const customerId of stripeCustomerIds) {
          const result = await deleteStripeCustomer(customerId, false);
          if (result.success) {
            stripeSuccessCount++;
            console.log(`  ✅ Deleted Stripe customer: ${customerId}`);
          } else if (result.skipped) {
            console.log(`  ⚠️  Skipped Stripe customer: ${customerId}`);
          } else {
            stripeFailCount++;
          }
        }

        console.log(`\n  Total Stripe customers deleted: ${stripeSuccessCount}/${stripeCustomerIds.length}`);
        if (stripeFailCount > 0) {
          console.log(`  ⚠️  Failed to delete ${stripeFailCount} Stripe customer(s)`);
        }
      }

      // Step 2: Delete database records
      console.log('\n🗑️  Deleting database records...');
      const dbResult = await deletePlayerAccounts(client, players, tablesExist, false);

      console.log(`  ✅ Deleted ${dbResult.playersDeleted} player profiles`);
      console.log(`  ✅ Deleted ${dbResult.accountsDeleted} user accounts`);
      console.log(`  ✅ Cascade deleted ${relatedCounts.sessions} sessions`);
      console.log(`  ✅ Cascade deleted ${relatedCounts.refreshTokens} refresh tokens`);
      console.log(`  ✅ Cascade deleted ${relatedCounts.apiKeys} API keys`);

      // Commit transaction
      await client.query('COMMIT');

      console.log('\n═'.repeat(60));
      console.log('\n✅ All player profiles deleted successfully!\n');

      // Summary
      console.log('Summary:');
      console.log(`  - Player profiles: ${dbResult.playersDeleted}`);
      console.log(`  - User accounts: ${dbResult.accountsDeleted}`);
      console.log(`  - Stripe customers: ${stripeCustomerIds.length}`);
      console.log(`  - Total database records: ${dbResult.playersDeleted + dbResult.accountsDeleted + relatedCounts.sessions + relatedCounts.refreshTokens + relatedCounts.apiKeys}\n`);
      console.log('═'.repeat(60) + '\n');

    } catch (error) {
      // Rollback transaction on error
      await client.query('ROLLBACK');
      throw error;
    }

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
    process.exit(1);
  } finally {
    await client.end();
    console.log('✅ Database connection closed\n');
  }
}

// Run the script
main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});
