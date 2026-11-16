'use client';
import {useEffect, useState} from 'react';
import {portalEmbed} from '../../../shared/portal-content';
import './portal-admin.css';

type Mod = {id: string; title: string; status: string};
type Video = {module: string; url: string; updated_at: string};

/** Central Vinha › Portal da Vinha: cole o link do vídeo (YouTube ou Vimeo) de cada módulo. O Portal mostra o vídeo na hora. */
export default function PortalAdmin() {
  const [mods, setMods] = useState<Mod[]>([]),
    [draft, setDraft] = useState<Record<string, string>>({}),
    [saved, setSaved] = useState<Record<string, Video>>({}),
    [busy, setBusy] = useState(''),
    [notice, setNotice] = useState(''),
    [error, setError] = useState('');
  const apply = (videos: Video[]) => {
    const map = Object.fromEntries(videos.map((v) => [v.module, v]));
    setSaved(map);
    setDraft(Object.fromEntries(videos.map((v) => [v.module, v.url])));
  };
  useEffect(() => {
    fetch('/api/platform/portal-videos', {cache: 'no-store'})
      .then(async (r) => {
        const d = (await r.json()) as {modules?: Mod[]; videos?: Video[]; error?: string};
        if (!r.ok) throw Error(d.error || 'Indisponível.');
        setMods(d.modules || []);
        apply(d.videos || []);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Indisponível.'));
  }, []);
  async function save(id: string, url: string) {
    setBusy(id);
    setError('');
    setNotice('');
    try {
      const r = await fetch('/api/platform/portal-videos', {method: 'PUT', headers: {'content-type': 'application/json'}, body: JSON.stringify({module: id, url})});
      const d = (await r.json()) as {videos?: Video[]; error?: string};
      if (!r.ok) throw Error(d.error || 'Não foi possível salvar.');
      apply(d.videos || []);
      setNotice(url ? 'Vídeo publicado no Portal da Vinha.' : 'Vídeo retirado do Portal da Vinha.');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível salvar.');
    } finally {
      setBusy('');
    }
  }
  return (
    <main className="team-chat-page pa">
      <a href="/admin-vinha">← Central da Vinha</a>
      <h1>Portal da Vinha</h1>
      <p>
        Cole o link do vídeo de cada módulo (YouTube ou Vimeo). Ele aparece no Portal da Vinha para todas as igrejas assim que for salvo. No YouTube, publique como “Não listado”
        se não quiser que o vídeo apareça em buscas.
      </p>
      {notice && <p role="status" className="pa-notice">{notice}</p>}
      {error && <p role="alert" className="pa-error">{error}</p>}
      <div className="pa-list">
        {mods.map((m) => {
          const value = draft[m.id] ?? '',
            embed = portalEmbed(value),
            changed = value.trim() !== (saved[m.id]?.url || '');
          return (
            <section key={m.id} className="pa-card">
              <div className="pa-head">
                <b>{m.title}</b>
                <small>{saved[m.id] ? 'Vídeo publicado · ' + new Date(saved[m.id]!.updated_at).toLocaleDateString('pt-BR') : 'Sem vídeo'}{m.status === 'em breve' ? ' · guia em breve' : ''}</small>
              </div>
              <label>
                Link do vídeo
                <input type="url" inputMode="url" placeholder="https://youtu.be/…" value={value} maxLength={300} onChange={(e) => setDraft({...draft, [m.id]: e.target.value})} />
              </label>
              {value && !embed && <small className="pa-error">Use um link do YouTube ou do Vimeo.</small>}
              {embed && <iframe className="pa-preview" src={embed} title={'Vídeo ' + m.title} allow="encrypted-media; picture-in-picture" allowFullScreen loading="lazy" />}
              <div className="pa-actions">
                {saved[m.id] && (
                  <button type="button" disabled={!!busy} onClick={() => window.confirm('Retirar o vídeo de ' + m.title + ' do Portal?') && void save(m.id, '')}>
                    Retirar vídeo
                  </button>
                )}
                <button type="button" className="pa-primary" disabled={!!busy || !changed || (!!value && !embed)} onClick={() => void save(m.id, value.trim())}>
                  {busy === m.id ? 'Salvando…' : 'Salvar'}
                </button>
              </div>
            </section>
          );
        })}
      </div>
    </main>
  );
}
