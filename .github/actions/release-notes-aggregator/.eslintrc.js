module.exports = {
  env: {
    es6: true
  },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/eslint-recommended',
    'plugin:@typescript-eslint/recommended'
  ],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    'project': 'tsconfig.json',
    'sourceType': 'module'
  },
  plugins: [
    '@typescript-eslint'
  ],
  rules: {
    'no-trailing-spaces': 'error',
    'no-console': 'off',

    'semi': ['error', 'never'],
    'indent': ['error', 2, { 'SwitchCase': 1 }],
    '@typescript-eslint/no-explicit-any': 'warn',
    '@typescript-eslint/no-unused-vars': ['error', { 'argsIgnorePattern': 'next|res|req' }],
    'func-call-spacing': 'error',
    'quotes': ['error', 'single'],
    'comma-spacing': ['error']
  }
};
