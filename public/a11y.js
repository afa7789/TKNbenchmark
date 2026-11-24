// Theme (light / dark / system) and font size, saved per browser under TKN-only keys.
// Classic script in <head>: the saved choice applies before the first paint; clicks are delegated,
// so the header ● switch and the accessibility panel drive the same state.
;(() => {
  const KEYS = { theme: 'tkn-theme', font: 'tkn-font-offset' }
  const FONT = { base: 16, step: 2, min: -2, max: 8 }
  const systemDark = matchMedia('(prefers-color-scheme: dark)')
  const root = document.documentElement
  const pref = {
    theme: localStorage.getItem(KEYS.theme) || 'system',
    font: Number(localStorage.getItem(KEYS.font)) || 0,
  }
  const $ = (id) => document.getElementById(id)

  function apply() {
    root.dataset.theme = pref.theme === 'system' ? (systemDark.matches ? 'dark' : 'light') : pref.theme
    root.style.fontSize = `${(100 * (FONT.base + pref.font)) / FONT.base}%`
    document.querySelectorAll('[data-a11y^="theme:"]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.a11y === `theme:${pref.theme}`)))
    if ($('a11y-font')) $('a11y-font').textContent = `${pref.font >= 0 ? '+' : ''}${pref.font}`
  }

  function save(key, value) {
    pref[key] = value
    localStorage.setItem(KEYS[key], String(value))
    apply()
  }

  function showPanel(open, refocus = true) {
    const panel = $('a11y-panel')
    if (!panel || panel.hidden === !open) return
    panel.hidden = !open
    $('a11y-toggle').setAttribute('aria-expanded', String(open))
    if (!open && refocus) $('a11y-toggle').focus()
  }

  const clampFont = (v) => Math.max(FONT.min, Math.min(FONT.max, v))
  const ACTIONS = {
    theme: (v) => save('theme', v),
    font: (v) => save('font', v === '0' ? 0 : clampFont(pref.font + Number(v) * FONT.step)),
    flip: () => save('theme', root.dataset.theme === 'dark' ? 'light' : 'dark'),
    panel: () => showPanel($('a11y-panel').hidden),
  }

  document.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-a11y]')
    if (btn) {
      const [action, value] = btn.dataset.a11y.split(':')
      ACTIONS[action](value)
    } else if (!e.target.closest('#a11y')) showPanel(false, false)
  })
  document.addEventListener('keydown', (e) => e.key === 'Escape' && showPanel(false))
  systemDark.addEventListener('change', () => pref.theme === 'system' && apply())
  document.addEventListener('DOMContentLoaded', apply)
  apply()
})()
