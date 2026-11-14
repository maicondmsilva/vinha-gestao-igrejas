'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {readApiError} from '../shared/contract/errors';

type State = {enabled: boolean; configured: boolean; updatedAt: string | null};

/** Telão (Holyrics): quando a sala chama um responsável, o telão mostra só o número da etiqueta e a sala. */
export default function KidsProjector({unit}: {unit: string}) {
  const [state, setState] = useState<State | null>(null),
    [enabled, setEnabled] = useState(false),
    [apiKey, setApiKey] = useState(''),
    [token, setToken] = useState(''),
    [busy, setBusy] = useState(''),
    [notice, setNotice] = useState('');
  const url = settingsUrl('/api/kids/projector?' + new URLSearchParams({unit}));
  useEffect(() => {
    let live = true;
    void fetch(url, {cache: 'no-store'})
      .then(async (r) => {
        const d = await r.json().catch(() => ({}));
        if (!live) return;
        if (!r.ok) {
          setNotice(readApiError(d).error);
          return;
        }
        setState(d as State);
        setEnabled((d as State).enabled);
      })
      .catch(() => live && setNotice('Sem conexão.'));
    return () => {
      live = false;
    };
  }, [url]);
  async function send(action: 'save' | 'test') {
    setBusy(action);
    setNotice('');
    const r = await fetch(url, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(action === 'save' ? {action, data: {enabled, apiKey, token}} : {action}),
    }).catch(() => null);
    const d = (r ? await r.json().catch(() => ({})) : {}) as {enabled: boolean; configured: boolean; ok?: boolean};
    setBusy('');
    if (!r || !r.ok) {
      setNotice(r ? readApiError(d).error : 'Sem conexão.');
      return;
    }
    if (action === 'save') {
      setState({enabled: d.enabled, configured: d.configured, updatedAt: new Date().toISOString()});
      setApiKey('');
      setToken('');
      setNotice(d.enabled ? 'Telão ligado. Os chamados da sala aparecem no Holyrics.' : 'Configuração salva. O telão está desligado.');
    } else
      setNotice(
        d.ok ? 'Teste enviado. Confira se a faixa "Teste do telão Kids pela Vinha" apareceu no telão.' : 'O teste não foi enviado. Revise a chave e o token.',
      );
  }
  return (
    <section className="ko-card">
      <div className="ko-card-title">
        <div>
          <h2>Telão (Holyrics)</h2>
          <p>
            Quando a sala chama um responsável, o telão mostra uma faixa como “Kids: responsável pela criança nº 27, compareça à Sala Azul”. Só o número da
            etiqueta aparece, nunca o nome da criança. A faixa some em 60 segundos ou quando o responsável responde no app.
          </p>
        </div>
      </div>
      {notice && (
        <p className="ko-notice" role="status">
          {notice}
        </p>
      )}
      {!state ? (
        <p className="ko-empty">Carregando…</p>
      ) : (
        <form
          className="ko-form-grid"
          onSubmit={(e) => {
            e.preventDefault();
            void send('save');
          }}
        >
          <label className="ko-check">
            <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} /> Mostrar os chamados do Kids no telão desta igreja
          </label>
          <label>
            Chave da API do Holyrics {state.configured && <small>(já salva; preencha só para trocar)</small>}
            <input type="password" autoComplete="off" value={apiKey} maxLength={200} onChange={(e) => setApiKey(e.target.value)} />
          </label>
          <label>
            Token de acesso {state.configured && <small>(já salvo; preencha só para trocar)</small>}
            <input type="password" autoComplete="off" value={token} maxLength={200} onChange={(e) => setToken(e.target.value)} />
          </label>
          <div className="ko-actions">
            <button type="submit" className="ko-primary" disabled={!!busy}>
              {busy === 'save' ? 'Salvando…' : 'Salvar'}
            </button>
            <button type="button" disabled={!!busy || !state.configured} onClick={() => void send('test')}>
              {busy === 'test' ? 'Enviando…' : 'Testar telão'}
            </button>
          </div>
        </form>
      )}
      <details>
        <summary>Como configurar no Holyrics</summary>
        <ol>
          <li>No computador do telão, abra o Holyrics em Arquivo › Configurações › API Server.</li>
          <li>Ative o acesso pela internet (web) e copie a chave da API (API Key).</li>
          <li>Em “Gerenciar permissões”, crie um token só para a Vinha e libere apenas a ação SetAlert.</li>
          <li>Cole a chave e o token aqui, marque “Mostrar os chamados” e toque em Testar telão.</li>
        </ol>
        <p>O computador do Holyrics precisa estar ligado e com internet durante o culto.</p>
      </details>
    </section>
  );
}
