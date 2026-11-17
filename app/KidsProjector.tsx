'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {readApiError} from '../shared/contract/errors';

type State = {enabled: boolean; configured: boolean; updatedAt: string | null};

/** Explica o resultado do teste do telão em linguagem simples. */
export function projectorMessage(state: string, response = '') {
  if (state === 'ok') return 'Chegou ao Holyrics. A faixa "Teste do telão Kids pela Vinha" deve aparecer por 10 segundos.';
  if (state === 'denied')
    return 'O Holyrics recusou: confira a chave (API_KEY) e o token, e se o token tem permissão para "SetAlert" (Holyrics › Arquivo › Configurações › API Server › gerenciar permissões).';
  if (state === 'network') return 'Não foi possível falar com o servidor do Holyrics agora. Tente de novo em instantes.';
  if (state === 'not_sent') return 'O envio não saiu do servidor. Avise o suporte Vinha.';
  return (
    'O Holyrics respondeu com erro. Confira se o programa está aberto e se o "acesso pela internet" do API Server está ativado.' +
    (response ? ' Resposta: ' + response.slice(0, 160) : '')
  );
}

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
        if (typeof (d as State).enabled !== 'boolean' || typeof (d as State).configured !== 'boolean') {
          setNotice('Não foi possível ler a configuração do telão. Atualize a página.');
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
    } else if (!d.ok) setNotice('O teste não foi enviado. Revise a chave e o token.');
    else {
      setNotice('Teste enviado. Aguardando a resposta do Holyrics…');
      // O Holyrics responde em alguns segundos: consulta o resultado e explica o que aconteceu.
      for (let i = 0; i < 6; i++) {
        await new Promise((ok) => setTimeout(ok, 2000));
        const x = await fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action: 'last'})}).catch(() => null);
        const s = (x?.ok ? await x.json().catch(() => ({})) : {}) as {state?: string; code?: number; response?: string};
        if (!s.state || s.state === 'waiting') continue;
        setNotice(projectorMessage(s.state, s.response));
        return;
      }
      setNotice('O Holyrics não respondeu. Confira se o programa está aberto no computador do telão e conectado à internet.');
    }
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
          className="ko-form-stack"
          onSubmit={(e) => {
            e.preventDefault();
            void send('save');
          }}
        >
          <label className="ko-check">
            <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />{' '}
            <span>Mostrar os chamados do Kids no telão desta igreja</span>
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

/** Situação do telão na Visão geral (só para quem configura): ligado, desligado ou sem configuração, com atalho para Configurar. */
export function KidsProjectorStatus({unit, onConfigure}: {unit: string; onConfigure: () => void}) {
  const [state, setState] = useState<State | null>(null);
  useEffect(() => {
    let live = true;
    void fetch(settingsUrl('/api/kids/projector?' + new URLSearchParams({unit})), {cache: 'no-store'})
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => live && d && typeof (d as State).enabled === 'boolean' && setState(d as State))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [unit]);
  if (!state) return null;
  const text = !state.configured
    ? 'Telão (Holyrics) não configurado'
    : state.enabled
      ? 'Telão (Holyrics) ligado: os chamados aparecem no culto'
      : 'Telão (Holyrics) desligado';
  return (
    <div className="ko-status-line" role="status">
      <p>
        <i className={state.configured && state.enabled ? 'on' : ''} aria-hidden />
        {text}
      </p>
      <button type="button" onClick={onConfigure}>
        {state.configured ? 'Telão e estações' : 'Configurar telão'}
      </button>
    </div>
  );
}
