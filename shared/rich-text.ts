// Notice text with light formatting, shared by the panel editor, the member portal and the ministry apps.
// Stored as plain text with a small Markdown subset, so old notices (plain text) still read the same:
//   ## Título · **negrito** · *itálico* · [texto](https://…) · - lista · 1. lista · > citação · ![descrição](img:<id>)
// The parser never produces HTML: each screen renders the blocks with its own components.

export type Inline =
  | {type: 'text'; text: string}
  | {type: 'bold'; children: Inline[]}
  | {type: 'italic'; children: Inline[]}
  | {type: 'link'; href: string; children: Inline[]};
export type Block =
  | {type: 'paragraph'; children: Inline[]}
  | {type: 'heading'; level: 2 | 3; children: Inline[]}
  | {type: 'list'; ordered: boolean; items: Inline[][]}
  | {type: 'quote'; children: Inline[]}
  | {type: 'image'; id: string; alt: string};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const imageLine = /^!\[([^\]\n]{0,240})\]\(img:([0-9a-f-]{36})\)\s*$/i;

/** Links allowed in notices: https pages, e-mail and phone. */
export function safeHref(href: string) {
  const h = href.trim();
  if (/^https:\/\/[^\s/@<>"\\]+\.[^\s/@<>"\\]+(\/[^\s<>"\\]*)?$/i.test(h)) return h;
  if (/^mailto:[^\s@<>"]+@[^\s@<>"]+\.[a-z]{2,}$/i.test(h)) return h;
  if (/^tel:\+?[0-9 ()-]{8,20}$/.test(h)) return h.replace(/[ ()-]/g, '');
  return null;
}

/** Inline marks: links first, then bold, then italic. Anything unmatched stays as text. */
export function parseInline(src: string): Inline[] {
  const out: Inline[] = [];
  const re = /\[([^\]\n]{1,200})\]\(([^)\s]{1,2000})\)|\*\*([^*\n]+?)\*\*|\*([^*\n]+?)\*/g;
  let last = 0,
    m: RegExpExecArray | null;
  const text = (t: string) => {
    if (!t) return;
    const prev = out[out.length - 1];
    if (prev?.type === 'text') prev.text += t;
    else out.push({type: 'text', text: t});
  };
  while ((m = re.exec(src))) {
    text(src.slice(last, m.index));
    if (m[1] !== undefined) {
      const href = safeHref(m[2]);
      if (href) out.push({type: 'link', href, children: parseInline(m[1]).filter((c) => c.type !== 'link')});
      else text(m[0]);
    } else if (m[3] !== undefined) out.push({type: 'bold', children: parseInline(m[3])});
    else out.push({type: 'italic', children: parseInline(m[4])});
    last = m.index + m[0].length;
  }
  text(src.slice(last));
  return out;
}

export function parseRichText(body: string): Block[] {
  const blocks: Block[] = [],
    lines = (body || '').replace(/\r\n?/g, '\n').split('\n');
  let para: string[] = [];
  const flush = () => {
    if (para.length) blocks.push({type: 'paragraph', children: parseInline(para.join('\n'))});
    para = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i],
      trimmed = line.trim();
    let m: RegExpExecArray | null;
    if (!trimmed) {
      flush();
      continue;
    }
    if ((m = imageLine.exec(trimmed)) && uuid.test(m[2])) {
      flush();
      blocks.push({type: 'image', id: m[2].toLowerCase(), alt: m[1].trim()});
      continue;
    }
    if ((m = /^(#{2,3})\s+(.+)$/.exec(trimmed))) {
      flush();
      blocks.push({type: 'heading', level: m[1].length as 2 | 3, children: parseInline(m[2])});
      continue;
    }
    if (/^>\s?/.test(trimmed)) {
      flush();
      const quote = [trimmed.replace(/^>\s?/, '')];
      while (i + 1 < lines.length && /^>\s?/.test(lines[i + 1].trim())) quote.push(lines[++i].trim().replace(/^>\s?/, ''));
      blocks.push({type: 'quote', children: parseInline(quote.join('\n'))});
      continue;
    }
    const bullet = /^[-*•]\s+(.+)$/,
      number = /^\d{1,3}[.)]\s+(.+)$/;
    if (bullet.test(trimmed) || number.test(trimmed)) {
      flush();
      const ordered = number.test(trimmed),
        pattern = ordered ? number : bullet,
        items: Inline[][] = [];
      i--;
      while (i + 1 < lines.length && pattern.test(lines[i + 1].trim())) items.push(parseInline(pattern.exec(lines[++i].trim())![1]));
      blocks.push({type: 'list', ordered, items});
      continue;
    }
    para.push(line);
  }
  flush();
  return blocks;
}

const inlineText = (nodes: Inline[]): string => nodes.map((n) => (n.type === 'text' ? n.text : inlineText(n.children))).join('');

/** Plain text for previews, push and lists (no marks, images become their description). */
export function richTextPlain(body: string, max = 4000) {
  const text = parseRichText(body)
    .map((b) =>
      b.type === 'image'
        ? b.alt
          ? `[${b.alt}]`
          : ''
        : b.type === 'list'
          ? b.items.map((i, n) => (b.ordered ? `${n + 1}. ` : '• ') + inlineText(i)).join('\n')
          : inlineText(b.children),
    )
    .filter(Boolean)
    .join('\n\n');
  return text.length > max ? text.slice(0, max - 1).trimEnd() + '…' : text;
}

/** Image ids used in the text (for the panel library and checks). */
export const richTextImages = (body: string) => parseRichText(body).flatMap((b) => (b.type === 'image' ? [b.id] : []));

/** Address of a library image, relative to the platform origin. */
export const publishingImagePath = (id: string) => '/api/publishing-images/' + id;
