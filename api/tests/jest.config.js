module.exports = {
  testEnvironment: 'node',
  coverageDirectory: '../coverage',
  collectCoverageFrom: [
    '../lib/**/*.js',
    '../functions/**/*.js',
    '!**/node_modules/**',
    '!**/tests/**',
  ],
  testMatch: [
    '**/*.test.js',
    '**/*.spec.js',
  ],
  setupFilesAfterEnv: ['./setup.js'],
  testTimeout: 30000,
  verbose: true,
  forceExit: true,
  clearMocks: true,
  resetMocks: true,
  restoreMocks: true,
};