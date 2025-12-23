module.exports = [
  {
    ignores: ['node_modules/**', 'dist/**'],
  },
  {
    files: ['**/*.js'],
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'commonjs',
      globals: {
        require: 'readonly',
        module: 'readonly',
        exports: 'readonly',
        __dirname: 'readonly',
        __filename: 'readonly',
        process: 'readonly',
        console: 'readonly',
        Buffer: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        fetch: 'readonly',
        AbortController: 'readonly',
      },
    },
    rules: {
      'no-unused-vars': 'warn',
      'no-undef': 'error',
      'semi': ['error', 'always'],
      'quotes': 'off',
    },
  },
];
