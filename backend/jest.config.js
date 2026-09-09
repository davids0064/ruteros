module.exports = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: '.',
  testEnvironment: 'node',
  testRegex: '\\.(spec|e2e-spec)\\.ts$',
  transform: { '^.+\\.ts$': 'ts-jest' },
  collectCoverageFrom: ['src/**/*.(t|j)s'],
  coverageDirectory: './coverage',
  // Testcontainers arranca PostgreSQL 15 real (04 §7): los triggers se
  // ejercitan de verdad, nunca contra un mock.
  testTimeout: 180000,
};
