'use client';
import {useCallback, useEffect, useRef, useState} from 'react';
import './cell-cover.css';

type Kind = 'cell' | 'network';
const url = (q: Record<string, string>) => '/api/cell-covers?' + new URLSearchParams(q);

/** Capas da igreja: um mapa {'cell:id': versão}. A versão força a nova imagem depois de trocar. */
export function useCellCovers(unit: string) {
  const [covers, setCovers] = useState<Record<string, number>>({}),
    [rev, setRev] = useState(0);
  useEffect(() => {
    if (!unit) return;
    const c = new AbortController();
    fetch(url({unit, list: '1'}), {cache: 'no-store', signal: c.signal})
      .then(async (r) => (r.ok ? await r.json() : {}) as {covers?: Record<string, number>})
      .then((d) => setCovers(d.covers || {}))
      .catch(() => {});
    return () => c.abort();
  }, [unit, rev]);
  return {covers, reload: useCallback(() => setRev((v) => v + 1), [])};
}

const palette = ['#285c45', '#3d6b8c', '#8a5a12', '#6d3f7a', '#2f7a6b', '#8c2f39'];
const hash = (s: string) => [...s].reduce((n, c) => (n * 31 + c.charCodeAt(0)) >>> 0, 7);

/** Capa do cartão (célula ou rede). Sem imagem: cor da igreja com as iniciais. Quem edita troca ou remove. */
export default function CellCover({
  unit,
  kind,
  id,
  name,
  version,
  canManage,
  changed,
}: {
  unit: string;
  kind: Kind;
  id: string;
  name: string;
  version?: number;
  canManage: boolean;
  changed: () => void;
}) {
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    input = useRef<HTMLInputElement>(null);
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
  async function send(file?: File) {
    if (!file) return;
    setError('');
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 3145728) {
      setError('Use JPEG, PNG ou WebP de até 3 MB.');
      return;
    }
    setBusy(true);
    try {
      const r = await fetch(url({unit, kind, id}), {method: 'POST', body: file});
      const d = (await r.json().catch(() => ({}))) as {error?: string};
      if (!r.ok) throw Error(d.error || 'Capa não enviada.');
      changed();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Capa não enviada.');
    } finally {
      setBusy(false);
      if (input.current) input.current.value = '';
    }
  }
  async function remove() {
    if (!window.confirm('Remover a capa de ' + name + '?')) return;
    setBusy(true);
    setError('');
    const r = await fetch(url({unit, kind, id}), {method: 'DELETE'}).catch(() => null);
    setBusy(false);
    if (!r?.ok) setError('Não foi possível remover.');
    else changed();
  }
  return (
    <div className={'cell-cover' + (version ? ' has-image' : '')} style={version ? undefined : {background: palette[hash(id) % palette.length]}}>
      {version ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={url({unit, kind, id, v: String(version)})} alt={'Capa de ' + name} loading="lazy" />
      ) : (
        <span aria-hidden>{initials}</span>
      )}
      {canManage && (
        <div className="cell-cover-actions">
          <button type="button" disabled={busy} onClick={() => input.current?.click()}>
            {busy ? 'Enviando…' : version ? 'Trocar capa' : 'Adicionar capa'}
          </button>
          {!!version && (
            <button type="button" disabled={busy} onClick={() => void remove()} aria-label={'Remover capa de ' + name}>
              ✕
            </button>
          )}
          <input ref={input} type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => void send(e.target.files?.[0])} />
        </div>
      )}
      {error && (
        <p className="cell-cover-error" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
