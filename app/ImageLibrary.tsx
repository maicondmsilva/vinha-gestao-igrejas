'use client';
import {useCallback, useEffect, useRef, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {readApiError} from '../shared/contract/errors';
import {publishingImagePath} from '../shared/rich-text';
import './rich-text.css';

export type LibraryImage = {id: string; name: string; alt: string; mime: string; bytes: number; createdAt: string};

/** Ministry image library: upload once, reuse in notices and banners. */
export default function ImageLibrary({unit, close, pick}: {unit: string; close: () => void; pick: (img: LibraryImage) => void}) {
  const [items, setItems] = useState<LibraryImage[] | null>(null),
    [page, setPage] = useState(1),
    [more, setMore] = useState(false),
    [search, setSearch] = useState(''),
    [query, setQuery] = useState(''),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState(''),
    file = useRef<HTMLInputElement>(null),
    panel = useRef<HTMLDivElement>(null);
  const base = '/api/publishing-images?' + new URLSearchParams({unit});
  const load = useCallback(
    async (p: number, q: string) => {
      const r = await fetch(settingsUrl(base + '&' + new URLSearchParams({page: String(p), search: q})), {cache: 'no-store'});
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw Error(readApiError(d).error);
      const list = (d as {items: LibraryImage[]}).items || [];
      return {list: list.slice(0, 30), more: list.length > 30};
    },
    [base],
  );
  useEffect(() => {
    let live = true;
    load(page, query)
      .then(({list, more}) => {
        if (!live) return;
        setItems((cur) => (page === 1 ? list : [...(cur || []), ...list]));
        setMore(more);
      })
      .catch((e) => live && setNotice((e as Error).message));
    return () => {
      live = false;
    };
  }, [page, query, load]);
  useEffect(() => {
    panel.current?.focus();
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && close();
    addEventListener('keydown', esc);
    return () => removeEventListener('keydown', esc);
  }, [close]);
  async function upload(f: File) {
    if (f.size > 5 * 1024 * 1024) return setNotice('A imagem precisa ter até 5 MB.');
    setBusy(true);
    setNotice('');
    try {
      const r = await fetch(settingsUrl(base + '&' + new URLSearchParams({name: f.name.replace(/\.[a-z0-9]+$/i, '').slice(0, 120) || 'Imagem'})), {
        method: 'POST',
        headers: {'Content-Type': f.type || 'application/octet-stream'},
        body: f,
      });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw Error(readApiError(d).error);
      const img = d as LibraryImage;
      setItems((cur) => [{...img, alt: '', bytes: f.size, createdAt: new Date().toISOString()}, ...(cur || [])]);
      setNotice('Imagem enviada. Clique nela para usar.');
    } catch (e) {
      setNotice((e as Error).message);
    } finally {
      setBusy(false);
      if (file.current) file.current.value = '';
    }
  }
  return (
    <div className="img-lib-modal" role="dialog" aria-modal="true" aria-labelledby="img-lib-title" onClick={(e) => e.target === e.currentTarget && close()}>
      <div className="img-lib-panel img-lib" ref={panel} tabIndex={-1}>
        <header>
          <h2 id="img-lib-title">Banco de imagens</h2>
          <button type="button" onClick={close}>
            Fechar
          </button>
        </header>
        <div className="img-lib-bar">
          <input
            type="search"
            placeholder="Buscar pelo nome"
            value={search}
            maxLength={80}
            onChange={(e) => setSearch(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                setPage(1);
                setQuery(search.trim());
              }
            }}
            aria-label="Buscar imagem"
          />
          <button type="button" disabled={busy} onClick={() => file.current?.click()}>
            {busy ? 'Enviando…' : 'Enviar imagem'}
          </button>
          <input
            ref={file}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            hidden
            onChange={(e) => e.target.files?.[0] && void upload(e.target.files[0])}
          />
        </div>
        <small>JPEG, PNG ou WebP de até 5 MB. As imagens ficam disponíveis para todas as igrejas em que você publica.</small>
        {notice && <p role="status">{notice}</p>}
        {!items ? (
          <p role="status">Carregando…</p>
        ) : !items.length ? (
          <p>Nenhuma imagem {query ? 'com esse nome' : 'ainda'}. Envie a primeira.</p>
        ) : (
          <div className="img-lib-grid">
            {items.map((img) => (
              <button key={img.id} type="button" onClick={() => pick(img)} aria-label={'Usar ' + img.name}>
                <img src={settingsUrl(publishingImagePath(img.id))} alt="" loading="lazy" />
                <span>{img.name}</span>
              </button>
            ))}
          </div>
        )}
        {more && (
          <button type="button" onClick={() => setPage((p) => p + 1)}>
            Mostrar mais
          </button>
        )}
      </div>
    </div>
  );
}
