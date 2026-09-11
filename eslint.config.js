import js from '@eslint/js';
import globals from 'globals';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import tseslint from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';
import prettierConfig from 'eslint-config-prettier';

export default [
  {
    // `supabase/functions` is Deno, not Node/browser — it has its own
    // toolchain (deno check + deno lint, run by the `edge-functions` CI
    // job and configured in supabase/functions/deno.json). Linting it here
    // only produces false `'Deno' is not defined` errors.
    ignores: [
      'dist',
      'node_modules',
      'supabase/.temp',
      'supabase/.branches',
      'supabase/functions',
      'docs/funda360-reference-other',
    ],
  },
  js.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: { ...globals.browser, ...globals.node },
      parser: tsParser,
      parserOptions: {
        ecmaFeatures: { jsx: true },
      },
    },
    plugins: {
      '@typescript-eslint': tseslint,
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
      'jsx-a11y': jsxA11y,
    },
    rules: {
      ...tseslint.configs.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      ...jsxA11y.configs.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-unused-vars': 'off',
    },
  },
  {
    // Standalone Node tooling scripts (e.g. supabase/load-tests/run.mjs) —
    // plain Node runtime, not the browser/React app, so this gets Node
    // globals instead of the browser block above.
    files: ['**/*.mjs'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: globals.node,
    },
  },
  prettierConfig,
];
