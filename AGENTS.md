# Repository Guidelines

## Project Structure & Module Organization
The application code resides in `api/`, with configuration helpers in `api/config`, shared utilities in `api/lib`, and Supabase Edge Functions grouped under `api/functions/<name>/`. HTTP and integration tests live in `api/tests`, while SQL schema modules and seed data are staged in `sql/modules` and `sql/seeds`. Compose files (`docker-compose*.yml`) and shell scripts (`migrate.sh`, `migrate-events.sh`) orchestrate local services, migrations, and Supabase alignment.

## Build, Test, and Development Commands
Install dependencies with `npm install` at the repository root. Use `npm run dev` for an auto-reloading Express gateway during iteration or `npm start` for production parity. Run `npm test` for the Jest suite or `npm run test:watch` while developing specs. Database workflows use `npm run db:migrate` to apply SQL modules and `npm run db:seed` for seed data. For container orchestration, `npm run docker:up` launches the full stack, `npm run docker:logs` tails services, and `npm run docker:down` tears it down when finished.

## Coding Style & Naming Conventions
Maintain two-space indentation and ES module syntax in all JavaScript and Deno Edge Function files. Prefer descriptive camelCase for variables and functions, PascalCase for classes, and kebab-case directories for Edge Functions (e.g., `send-email`). Keep environment-driven configuration in `api/config` and avoid hard-coding secrets. Align SQL modules with the numeric prefixes already in `sql/modules` so migrations run deterministically.

## Testing Guidelines
Jest is configured via `api/tests/jest.config.js`; locate new specs in `api/tests` and name them `<feature>.test.js`. Integration paths should exercise the Express handlers with Supertest and stub Supabase interactions where possible. Before opening a pull request, ensure `npm test` passes and validate new SQL by running `npm run db:migrate` against a fresh container.

## Commit & Pull Request Guidelines
Follow a Conventional Commits style summary (e.g., `feat: add events edge function`) to describe the change scope succinctly. Each pull request should include a concise problem statement, a walkthrough of the solution, database migration notes if applicable, and screenshots or API responses when the change affects external behavior. Reference related issues and call out any manual verification steps executed locally.

## Security & Configuration Tips
Manage secrets through the `.env` file mirrored in `.env.local`; never commit credentials. When running Supabase locally, use `npm run supabase:start` and `npm run supabase:stop` to align with the cloud configuration, and consult `README-SUPABASE.md` for environment-specific overrides.
