// Minimal, safe-ish Markdown renderer for streaming chat
// Supports: headings, bold, italic, inline code, fenced code blocks, links, lists, line breaks

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function isSafeUrl(url) {
  try {
    const u = new URL(url)
    return u.protocol === 'http:' || u.protocol === 'https:'
  } catch (_) {
    return false
  }
}

export function renderMarkdown(input) {
  if (!input) return ''

  // Always work on escaped text first
  let text = escapeHtml(String(input))

  // Handle fenced code blocks ```lang\ncode\n```
  const codeBlocks = []
  text = text.replace(/```([a-zA-Z0-9_-]+)?\n([\s\S]*?)```/g, (_, lang, code) => {
    const idx = codeBlocks.length
    codeBlocks.push({ lang: lang || '', code })
    return `@@CODE_BLOCK_${idx}@@`
  })

  // Headings: # ... up to ###### ...
  text = text.replace(/^######\s+(.*)$/gm, '<h6>$1</h6>')
             .replace(/^#####\s+(.*)$/gm, '<h5>$1</h5>')
             .replace(/^####\s+(.*)$/gm, '<h4>$1</h4>')
             .replace(/^###\s+(.*)$/gm, '<h3>$1</h3>')
             .replace(/^##\s+(.*)$/gm, '<h2>$1</h2>')
             .replace(/^#\s+(.*)$/gm, '<h1>$1</h1>')

  // Unordered lists (simple): lines starting with - or *
  // Group consecutive list items into <ul>
  text = text.replace(/(^|\n)([\-*]\s.+(?:\n[\-*]\s.+)*)/g, (m, lead, block) => {
    const items = block.split(/\n/).map(l => l.replace(/^[\-*]\s+/, '').trim())
    const lis = items.map(i => `<li>${i}</li>`).join('')
    return `${lead}<ul>${lis}</ul>`
  })

  // Inline code: `code`
  text = text.replace(/`([^`]+)`/g, '<code>$1</code>')

  // Bold: **text** or __text__
  text = text.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
             .replace(/__([^_]+)__/g, '<strong>$1</strong>')

  // Italic: *text* or _text_ (avoid matching inside HTML tags)
  text = text.replace(/\*(?!\*)([^*]+)\*/g, '<em>$1</em>')
             .replace(/_(?!_)([^_]+)_/g, '<em>$1</em>')

  // Links: [text](url)
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (m, label, url) => {
    if (!isSafeUrl(url)) return label
    return `<a href="${url}" target="_blank" rel="noopener noreferrer">${label}</a>`
  })

  // Line breaks
  text = text.replace(/\n/g, '<br>')

  // Restore code blocks at the end
  text = text.replace(/@@CODE_BLOCK_(\d+)@@/g, (_, i) => {
    const { lang, code } = codeBlocks[Number(i)] || { lang: '', code: '' }
    // code is already escaped earlier
    const cls = lang ? ` class="language-${lang}"` : ''
    return `<pre><code${cls}>${code}</code></pre>`
  })

  return text
}

