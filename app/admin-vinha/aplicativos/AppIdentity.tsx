'use client';
import {useCallback, useEffect, useState} from 'react';
import {createSupabaseBrowserClient} from '../../lib/supabase/client';

type Opening = {kind: 'none' | 'image' | 'video'; url: string; title: string; seconds: number; version: number};
type Identity = {
  appName: string;
  primaryColor: string;
  accentColor: string;
  updatedAt: string;
  logo: string | null;
  opening: Opening;
  iconUrl: string | null;
  released: boolean;
  canEdit: boolean;
};
type Notice = {kind: 'ok' | 'error'; text: string} | null;

async function api<T>(method: string, body?: unknown, org?: string): Promise<T> {
  const r = await fetch('/api/platform/apps/identity' + (org ? '?org=' + org : ''), {
    method,
    cache: 'no-store',
    headers: body ? {'content-type': 'application/json'} : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const d = (await r.json().catch(() => ({}))) as T & {error?: string};
  if (!r.ok) throw new Error(d.error || 'Não foi possível concluir.');
  return d;
}
const readDataUrl = (file: File) =>
  new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('Falha ao ler o arquivo.'));
    reader.readAsDataURL(file);
  });

/** Identidade do app do ministério: definida somente pela equipe da Vinha. */
export default function AppIdentity({organizationId, onChanged}: {organizationId: string; onChanged: () => void}) {
  const [data, setData] = useState<Identity | null>(null),
    [form, setForm] = useState({appName: '', primaryColor: '#285c45', accentColor: '#d8b769'}),
    [opening, setOpening] = useState<Opening>({kind: 'none', url: '', title: '', seconds: 5, version: 0}),
    [busy, setBusy] = useState(''),
    [notice, setNotice] = useState<Notice>(null);

  const apply = useCallback((d: Identity) => {
    setData(d);
    setForm({appName: d.appName, primaryColor: d.primaryColor, accentColor: d.accentColor});
    setOpening(d.opening);
  }, []);
  useEffect(() => {
    let live = true;
    setData(null);
    setNotice(null);
    api<Identity>('GET', undefined, organizationId)
      .then((d) => live && apply(d))
      .catch((e: Error) => live && setNotice({kind: 'error', text: e.message}));
    return () => {
      live = false;
    };
  }, [organizationId, apply]);

  async function run(label: string, task: () => Promise<Identity>, ok: string) {
    setBusy(label);
    setNotice(null);
    try {
      apply(await task());
      setNotice({kind: 'ok', text: ok});
      onChanged();
    } catch (e) {
      setNotice({kind: 'error', text: e instanceof Error ? e.message : 'Não foi possível concluir.'});
    } finally {
      setBusy('');
    }
  }
  const save = (action: string, payload: Record<string, unknown>) => api<Identity>('PATCH', {organizationId, action, data: payload});
  async function upload(kind: 'opening-image' | 'opening-video' | 'icon', file: File) {
    const link = await api<{path: string; token: string; publicUrl: string}>('POST', {organizationId, kind, contentType: file.type, size: file.size});
    const r = await createSupabaseBrowserClient().storage.from('vinha-app-assets').uploadToSignedUrl(link.path, link.token, file, {contentType: file.type});
    if (r.error) throw new Error('O envio do arquivo falhou. Tente novamente.');
    return link.publicUrl;
  }

  async function chooseLogo(file?: File) {
    if (!file) return;
    await run(
      'logo',
      async () => {
        if (file.type !== 'image/png' || file.size > 256000) throw new Error('A logo deve ser PNG de até 250 KB.');
        const bmp = await createImageBitmap(file);
        const okSize = bmp.width <= 2000 && bmp.height <= 2000 && bmp.width * bmp.height <= 2000000;
        bmp.close();
        if (!okSize) throw new Error('Use até 2.000 pixels por lado.');
        return save('logo', {logo: await readDataUrl(file)});
      },
      'Logo atualizada. O app mostra a nova logo na próxima abertura.',
    );
  }
  async function chooseOpening(file?: File) {
    if (!file) return;
    const video = file.type === 'video/mp4';
    setBusy('upload');
    setNotice(null);
    try {
      const url = await upload(video ? 'opening-video' : 'opening-image', file);
      setOpening((o) => ({...o, kind: video ? 'video' : 'image', url}));
      setNotice({kind: 'ok', text: 'Arquivo enviado. Confira a prévia e clique em Salvar abertura.'});
    } catch (e) {
      setNotice({kind: 'error', text: e instanceof Error ? e.message : 'Envio falhou.'});
    } finally {
      setBusy('');
    }
  }
  async function chooseIcon(file?: File) {
    if (!file) return;
    await run(
      'icon',
      async () => {
        if (file.type !== 'image/png' || file.size > 1048576) throw new Error('O ícone deve ser PNG de até 1 MB.');
        const bmp = await createImageBitmap(file);
        const square = bmp.width === 1024 && bmp.height === 1024;
        bmp.close();
        if (!square) throw new Error('O ícone deve ter exatamente 1024 × 1024 pixels.');
        return save('icon', {url: await upload('icon', file)});
      },
      'Ícone salvo. Ele entra no app na próxima geração (gerar-teste ou gerar-loja).',
    );
  }

  if (!data)
    return (
      <section className="apps-identity">
        {notice ? <div className={'apps-notice ' + notice.kind}>{notice.text}</div> : <p className="apps-empty">Carregando identidade…</p>}
      </section>
    );
  const off = !data.canEdit || Boolean(busy);
  return (
    <section className="apps-identity" aria-label="Identidade do aplicativo">
      <header>
        <h3>Identidade do aplicativo</h3>
        <p>
          Feita somente pela equipe da Vinha. O ministério vê estes dados no painel, mas não altera. Nome, cores, logo e abertura chegam ao app sem gerar nova
          versão; o ícone entra na próxima geração.
        </p>
      </header>
      {notice && (
        <div className={'apps-notice ' + notice.kind} role={notice.kind === 'error' ? 'alert' : 'status'}>
          {notice.text}
        </div>
      )}
      <div className="apps-identity-grid">
        <form
          className="apps-card"
          onSubmit={(e) => {
            e.preventDefault();
            void run('identity', () => save('identity', {...form, updatedAt: data.updatedAt}), 'Nome e cores salvos.');
          }}
        >
          <h4>Nome e cores</h4>
          <label>
            Nome dentro do app
            <input required minLength={2} maxLength={60} disabled={off} value={form.appName} onChange={(e) => setForm({...form, appName: e.target.value})} />
          </label>
          <div className="apps-two">
            {(['primaryColor', 'accentColor'] as const).map((k) => (
              <label key={k}>
                {k === 'primaryColor' ? 'Cor principal' : 'Cor de destaque'}
                <span className="apps-color">
                  <input type="color" disabled={off} value={form[k]} onChange={(e) => setForm({...form, [k]: e.target.value})} />
                  <code>{form[k]}</code>
                </span>
              </label>
            ))}
          </div>
          {data.canEdit && (
            <button className="primary" disabled={off}>
              {busy === 'identity' ? 'Salvando…' : 'Salvar nome e cores'}
            </button>
          )}
        </form>

        <div className="apps-card">
          <h4>Logo do ministério</h4>
          <div className="apps-media-box" style={{background: form.primaryColor}}>
            {data.logo ? <img src={data.logo} alt="Logo do ministério" /> : <span>Sem logo: o app usa a identidade da Vinha.</span>}
          </div>
          {data.canEdit && (
            <div className="apps-file-actions">
              <label className="apps-file">
                {busy === 'logo' ? 'Enviando…' : data.logo ? 'Trocar logo' : 'Enviar logo'}
                <input type="file" accept="image/png" disabled={off} onChange={(e) => void chooseLogo(e.target.files?.[0])} />
              </label>
              {data.logo && (
                <button type="button" disabled={off} onClick={() => void run('logo', () => save('logo', {logo: ''}), 'Logo removida.')}>
                  Remover
                </button>
              )}
            </div>
          )}
          <small>PNG com fundo transparente, até 250 KB.</small>
        </div>

        <form
          className="apps-card"
          onSubmit={(e) => {
            e.preventDefault();
            void run(
              'opening',
              () => save('opening', {...opening, url: opening.kind === 'none' ? '' : opening.url}),
              'Abertura salva. Os membros veem na próxima vez que abrirem o app.',
            );
          }}
        >
          <h4>Abertura do app</h4>
          <label>
            Mostrar ao abrir
            <select disabled={off} value={opening.kind} onChange={(e) => setOpening({...opening, kind: e.target.value as Opening['kind']})}>
              <option value="none">Somente a logo</option>
              <option value="image">Foto</option>
              <option value="video">Vídeo (MP4, sem som)</option>
            </select>
          </label>
          {opening.kind !== 'none' && (
            <>
              <div className="apps-media-box" style={{background: form.primaryColor}}>
                {opening.url ? (
                  opening.kind === 'video' ? (
                    <video src={opening.url} muted autoPlay loop playsInline />
                  ) : (
                    <img src={opening.url} alt="Prévia da abertura" />
                  )
                ) : (
                  <span>Envie o arquivo da abertura.</span>
                )}
              </div>
              {data.canEdit && (
                <label className="apps-file">
                  {busy === 'upload' ? 'Enviando…' : opening.kind === 'video' ? 'Enviar vídeo MP4 (até 50 MB)' : 'Enviar foto (até 5 MB)'}
                  <input
                    type="file"
                    accept={opening.kind === 'video' ? 'video/mp4' : 'image/jpeg,image/png,image/webp'}
                    disabled={off}
                    onChange={(e) => void chooseOpening(e.target.files?.[0])}
                  />
                </label>
              )}
            </>
          )}
          <label>
            Mensagem de boas-vindas
            <input
              maxLength={160}
              disabled={off}
              value={opening.title}
              placeholder="Bem-vindo à sua igreja"
              onChange={(e) => setOpening({...opening, title: e.target.value})}
            />
          </label>
          <label>
            Duração máxima (segundos)
            <input
              type="number"
              min={1}
              max={15}
              disabled={off}
              value={opening.seconds}
              onChange={(e) => setOpening({...opening, seconds: Number(e.target.value)})}
            />
          </label>
          {data.canEdit && (
            <button className="primary" disabled={off || (opening.kind !== 'none' && !opening.url)}>
              {busy === 'opening' ? 'Salvando…' : 'Salvar abertura'}
            </button>
          )}
        </form>

        <div className="apps-card">
          <h4>Ícone na tela do celular</h4>
          <div className="apps-icon-preview">
            {data.iconUrl ? (
              <img src={data.iconUrl} alt="Ícone do app" />
            ) : (
              <i style={{background: form.primaryColor}}>{form.appName.slice(0, 1).toUpperCase()}</i>
            )}
            <small>{data.iconUrl ? 'Ícone próprio' : 'Ícone padrão da Vinha'}</small>
          </div>
          {data.canEdit &&
            (data.released ? (
              <div className="apps-file-actions">
                <label className="apps-file">
                  {busy === 'icon' ? 'Enviando…' : data.iconUrl ? 'Trocar ícone' : 'Enviar ícone'}
                  <input type="file" accept="image/png" disabled={off} onChange={(e) => void chooseIcon(e.target.files?.[0])} />
                </label>
                {data.iconUrl && (
                  <button
                    type="button"
                    disabled={off}
                    onClick={() => void run('icon', () => save('icon', {url: null}), 'Ícone removido: volta ao padrão da Vinha na próxima geração.')}
                  >
                    Remover
                  </button>
                )}
              </div>
            ) : (
              <p className="apps-hint">Libere o aplicativo para enviar o ícone.</p>
            ))}
          <small>PNG 1024 × 1024, sem transparência nas bordas e com a arte centralizada (margem de 20%). Entra no app na próxima geração.</small>
        </div>
      </div>
    </section>
  );
}
