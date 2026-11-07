'use client';
import {useRef, useState} from 'react';
import RichText from './RichText';
import ImageLibrary from './ImageLibrary';
import {richTextImages} from '../shared/rich-text';
import './rich-text.css';

type Mark = {label: string; title: string; apply: (sel: string) => {text: string; cursor?: number}; block?: boolean};

const prefixLines = (sel: string, prefix: (i: number) => string) =>
  (sel || 'Texto')
    .split('\n')
    .map((l, i) => prefix(i) + l.replace(/^(#{2,3}\s+|[-*•]\s+|\d{1,3}[.)]\s+|>\s?)/, ''))
    .join('\n');
const marks: Mark[] = [
  {label: 'N', title: 'Negrito', apply: (s) => ({text: `**${s || 'texto em negrito'}**`})},
  {label: 'I', title: 'Itálico', apply: (s) => ({text: `*${s || 'texto em itálico'}*`})},
  {label: 'T', title: 'Título', apply: (s) => ({text: prefixLines(s || 'Título', () => '## ')}), block: true},
  {label: '•', title: 'Lista', apply: (s) => ({text: prefixLines(s, () => '- ')}), block: true},
  {label: '1.', title: 'Lista numerada', apply: (s) => ({text: prefixLines(s, (i) => `${i + 1}. `)}), block: true},
  {label: '❝', title: 'Destaque', apply: (s) => ({text: prefixLines(s, () => '> ')}), block: true},
];

/** Notice editor: plain textarea with formatting buttons, preview and the image library. Saves under `name`. */
export default function RichTextEditor({
  unit,
  name,
  defaultValue,
  label,
  max = 4000,
}: {
  unit: string;
  name: string;
  defaultValue: string;
  label: string;
  max?: number;
}) {
  const [value, setValue] = useState(defaultValue),
    [preview, setPreview] = useState(false),
    [library, setLibrary] = useState(false),
    area = useRef<HTMLTextAreaElement>(null);
  function insert(build: (sel: string) => {text: string}, block = false) {
    const el = area.current;
    if (!el) return;
    const start = el.selectionStart,
      end = el.selectionEnd,
      sel = value.slice(start, end),
      {text} = build(sel),
      before = value.slice(0, start),
      // Block marks start on their own line.
      lead = block && before && !before.endsWith('\n') ? '\n' : '',
      next = (before + lead + text + value.slice(end)).slice(0, max);
    setValue(next);
    requestAnimationFrame(() => {
      el.focus();
      const pos = Math.min(next.length, start + lead.length + text.length);
      el.setSelectionRange(pos, pos);
    });
  }
  function link() {
    const url = prompt('Endereço do link (https://…, mailto: ou tel:)');
    if (url) insert((s) => ({text: `[${s || 'texto do link'}](${url.trim()})`}));
  }
  const images = richTextImages(value).length;
  return (
    <div className="rte">
      <span id={name + '-label'}>{label}</span>
      <div className="rte-toolbar" role="toolbar" aria-label="Formatação do texto">
        {marks.map((m) => (
          <button key={m.title} type="button" title={m.title} aria-label={m.title} disabled={preview} onClick={() => insert(m.apply, m.block)}>
            {m.label}
          </button>
        ))}
        <button type="button" title="Link" aria-label="Link" disabled={preview} onClick={link}>
          🔗
        </button>
        <button type="button" title="Imagem do banco de imagens" aria-label="Imagem" disabled={preview || images >= 10} onClick={() => setLibrary(true)}>
          🖼
        </button>
        <button type="button" aria-pressed={preview} onClick={() => setPreview((p) => !p)}>
          {preview ? 'Editar' : 'Ver como fica'}
        </button>
      </div>
      {/* The textarea stays in the form (hidden during preview) so the value is always submitted. */}
      <textarea
        ref={area}
        name={name}
        rows={8}
        maxLength={max}
        value={value}
        onChange={(e) => setValue(e.target.value)}
        aria-labelledby={name + '-label'}
        hidden={preview}
        placeholder="Escreva o aviso. Use os botões para negrito, títulos, listas, links e imagens."
      />
      {preview && (
        <div className="rte-preview" aria-live="polite">
          {value.trim() ? <RichText body={value} /> : <p>Nada escrito ainda.</p>}
        </div>
      )}
      <div className="rte-meta">
        <span>{images ? `${images} ${images === 1 ? 'imagem' : 'imagens'} no texto (até 10)` : 'Dica: selecione um trecho e clique em N para negrito.'}</span>
        <span>
          {value.length}/{max}
        </span>
      </div>
      {library && (
        <ImageLibrary
          unit={unit}
          close={() => setLibrary(false)}
          pick={(img) => {
            setLibrary(false);
            insert(() => ({text: `![${(img.alt || img.name).replace(/[\[\]\n]/g, ' ').slice(0, 240)}](img:${img.id})\n`}), true);
          }}
        />
      )}
    </div>
  );
}
