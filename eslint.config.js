import js from '@eslint/js'
import globals from 'globals'

export default [
  { ignores: ['runs/**', 'runs-*/**', 'public/data/**', 'node_modules/**'] },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.browser, ...globals.node },
    },
    rules: { complexity: ['error', 10] },
  },
]
