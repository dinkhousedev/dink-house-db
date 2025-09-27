#!/usr/bin/env node

/**
 * CLI tool for creating admin accounts in the Dink House database
 * This tool allows creation of admin users with proper authorization
 */

require('dotenv').config();
const { Command } = require('commander');
const bcrypt = require('bcrypt');
const { Client } = require('pg');
const { v4: uuidv4 } = require('uuid');

// Database configuration
const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 9432,
  database: process.env.POSTGRES_DB || 'dink_house',
  user: process.env.POSTGRES_USER || 'postgres',
  password: process.env.POSTGRES_PASSWORD || 'DevPassword123!',
};

// Admin roles as defined in the database enum
const ADMIN_ROLES = ['super_admin', 'admin', 'manager', 'coach', 'editor', 'viewer'];

// Initialize commander
const program = new Command();

program
  .name('create-admin')
  .description('CLI tool to create admin accounts in Dink House database')
  .version('1.0.0');

program
  .option('-e, --email <email>', 'Admin email address')
  .option('-f, --firstName <firstName>', 'Admin first name')
  .option('-l, --lastName <lastName>', 'Admin last name')
  .option('-u, --username <username>', 'Admin username')
  .option('-r, --role <role>', 'Admin role (super_admin, admin, manager, coach, editor, viewer)')
  .option('-p, --password <password>', 'Admin password')
  .option('-d, --department <department>', 'Admin department')
  .option('--phone <phone>', 'Admin phone number')
  .option('--pre-authorize', 'Also add to allowed_emails table for web sign-up')
  .option('--no-interactive', 'Run in non-interactive mode (all required fields must be provided)')
  .parse(process.argv);

const options = program.opts();

/**
 * Validate email format
 */
function validateEmail(email) {
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return re.test(email);
}

/**
 * Validate password strength
 */
function validatePassword(password) {
  if (password.length < 8) {
    return 'Password must be at least 8 characters long';
  }
  if (!/[A-Z]/.test(password)) {
    return 'Password must contain at least one uppercase letter';
  }
  if (!/[a-z]/.test(password)) {
    return 'Password must contain at least one lowercase letter';
  }
  if (!/[0-9]/.test(password)) {
    return 'Password must contain at least one number';
  }
  return true;
}

/**
 * Generate a random password
 */
function generatePassword() {
  const length = 12;
  const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
  let password = '';
  for (let i = 0; i < length; i++) {
    password += charset.charAt(Math.floor(Math.random() * charset.length));
  }
  return password;
}

/**
 * Get user input interactively
 */
async function getInteractiveInput() {
  const inquirer = await import('inquirer');
  const questions = [];

  if (!options.email) {
    questions.push({
      type: 'input',
      name: 'email',
      message: 'Admin email address:',
      validate: (input) => validateEmail(input) || 'Please enter a valid email address',
    });
  }

  if (!options.firstName) {
    questions.push({
      type: 'input',
      name: 'firstName',
      message: 'First name:',
      validate: (input) => input.length > 0 || 'First name is required',
    });
  }

  if (!options.lastName) {
    questions.push({
      type: 'input',
      name: 'lastName',
      message: 'Last name:',
      validate: (input) => input.length > 0 || 'Last name is required',
    });
  }

  if (!options.username) {
    questions.push({
      type: 'input',
      name: 'username',
      message: 'Username:',
      validate: (input) => input.length >= 3 || 'Username must be at least 3 characters',
    });
  }

  if (!options.role) {
    questions.push({
      type: 'list',
      name: 'role',
      message: 'Admin role:',
      choices: ADMIN_ROLES,
      default: 'viewer',
    });
  }

  if (!options.password) {
    questions.push({
      type: 'password',
      name: 'password',
      message: 'Password (leave empty to generate):',
      validate: (input) => {
        if (!input) return true; // Allow empty for generation
        const result = validatePassword(input);
        return result === true ? true : result;
      },
    });
  }

  if (!options.department) {
    questions.push({
      type: 'input',
      name: 'department',
      message: 'Department (optional):',
    });
  }

  if (!options.phone) {
    questions.push({
      type: 'input',
      name: 'phone',
      message: 'Phone number (optional):',
    });
  }

  if (options.preAuthorize === undefined) {
    questions.push({
      type: 'confirm',
      name: 'preAuthorize',
      message: 'Also add to allowed_emails table for web sign-up?',
      default: true,
    });
  }

  const answers = await inquirer.default.prompt(questions);
  return { ...options, ...answers };
}

/**
 * Create admin account in database
 */
async function createAdminAccount(adminData) {
  const client = new Client(dbConfig);

  try {
    await client.connect();
    console.log('\n✓ Connected to database');

    // Start transaction
    await client.query('BEGIN');

    // Check if email already exists
    const checkEmail = await client.query(
      'SELECT id FROM app_auth.user_accounts WHERE email = $1',
      [adminData.email.toLowerCase()]
    );

    if (checkEmail.rows.length > 0) {
      throw new Error('An account with this email already exists');
    }

    // Check if username already exists
    const checkUsername = await client.query(
      'SELECT id FROM app_auth.admin_users WHERE username = $1',
      [adminData.username.toLowerCase()]
    );

    if (checkUsername.rows.length > 0) {
      throw new Error('This username is already taken');
    }

    // Generate password if not provided
    if (!adminData.password) {
      adminData.password = generatePassword();
      console.log('\n✓ Generated password:', adminData.password);
      console.log('  (Please save this password securely)');
    }

    // Hash password using database function
    const hashResult = await client.query(
      'SELECT hash_password($1) as password_hash',
      [adminData.password]
    );
    const passwordHash = hashResult.rows[0].password_hash;

    // Create user account
    const accountId = uuidv4();
    await client.query(
      `INSERT INTO app_auth.user_accounts
       (id, email, password_hash, user_type, is_active, is_verified, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      [accountId, adminData.email.toLowerCase(), passwordHash, 'admin', true, true]
    );
    console.log('✓ Created user account');

    // Create admin profile
    const adminId = uuidv4();
    await client.query(
      `INSERT INTO app_auth.admin_users
       (id, account_id, username, first_name, last_name, role, department, phone, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
      [
        adminId,
        accountId,
        adminData.username.toLowerCase(),
        adminData.firstName,
        adminData.lastName,
        adminData.role,
        adminData.department || null,
        adminData.phone || null,
      ]
    );
    console.log('✓ Created admin profile');

    // Add to allowed_emails if requested
    if (adminData.preAuthorize) {
      // Check if email is already in allowed_emails
      const checkAllowed = await client.query(
        'SELECT id, used_at FROM app_auth.allowed_emails WHERE email = $1',
        [adminData.email.toLowerCase()]
      );

      if (checkAllowed.rows.length === 0) {
        // Add to allowed_emails
        await client.query(
          `INSERT INTO app_auth.allowed_emails
           (id, email, first_name, last_name, role, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
          [
            uuidv4(),
            adminData.email.toLowerCase(),
            adminData.firstName,
            adminData.lastName,
            adminData.role,
            true,
          ]
        );
        console.log('✓ Added to allowed_emails table');
      } else if (checkAllowed.rows[0].used_at === null) {
        // Update existing allowed_email entry
        await client.query(
          `UPDATE app_auth.allowed_emails
           SET used_at = CURRENT_TIMESTAMP, used_by = $1, updated_at = CURRENT_TIMESTAMP
           WHERE email = $2`,
          [adminId, adminData.email.toLowerCase()]
        );
        console.log('✓ Updated allowed_emails entry');
      }
    }

    // Commit transaction
    await client.query('COMMIT');
    console.log('\n✅ Admin account created successfully!');
    console.log('\nAccount Details:');
    console.log('  Email:', adminData.email);
    console.log('  Username:', adminData.username);
    console.log('  Role:', adminData.role);
    console.log('  Name:', `${adminData.firstName} ${adminData.lastName}`);

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('\n❌ Error creating admin account:', error.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

/**
 * Main function
 */
async function main() {
  console.log('🔧 Dink House Admin Account Creator\n');

  let adminData;

  if (options.interactive !== false) {
    // Interactive mode
    adminData = await getInteractiveInput();
  } else {
    // Non-interactive mode - validate required fields
    if (!options.email || !options.firstName || !options.lastName || !options.username || !options.role) {
      console.error('❌ In non-interactive mode, you must provide: --email, --firstName, --lastName, --username, --role');
      process.exit(1);
    }

    if (!validateEmail(options.email)) {
      console.error('❌ Invalid email address');
      process.exit(1);
    }

    if (!ADMIN_ROLES.includes(options.role)) {
      console.error(`❌ Invalid role. Must be one of: ${ADMIN_ROLES.join(', ')}`);
      process.exit(1);
    }

    if (options.password) {
      const passwordValid = validatePassword(options.password);
      if (passwordValid !== true) {
        console.error(`❌ ${passwordValid}`);
        process.exit(1);
      }
    }

    adminData = options;
  }

  // Confirm creation
  if (options.interactive !== false) {
    const inquirer = await import('inquirer');
    const confirm = await inquirer.default.prompt([
      {
        type: 'confirm',
        name: 'confirm',
        message: `\nCreate admin account for ${adminData.email}?`,
        default: true,
      },
    ]);

    if (!confirm.confirm) {
      console.log('❌ Admin creation cancelled');
      process.exit(0);
    }
  }

  // Create the admin account
  await createAdminAccount(adminData);
}

// Run the main function
main().catch((error) => {
  console.error('❌ Unexpected error:', error);
  process.exit(1);
});