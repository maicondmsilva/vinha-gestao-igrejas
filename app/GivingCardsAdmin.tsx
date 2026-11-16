'use client';
import {useCallback, useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import ImageLibrary from './ImageLibrary';
import {publishingImagePath} from '../shared/rich-text';
import {givingAmountsFromText, givingAmountsText, givingPresets, givingSuggestions, type GivingAdminCard, type GivingAdminPage} from '../shared/giving';
import './giving-cards.css';

const blank = (): GivingAdminCard => ({
  id: crypto.randomUUID(),
  title: '',
  subtitle: '',
  image: '',
  color: givingPresets[0]!,
  amounts: [],
  position: 0,
  active: true,
  version: 0,
  category: '',
  ready: false,
});

/** Financeiro › Contribua no app: cartões de contribuição com a identidade da igreja, pagos pela conta principal. */
export default function GivingCardsAdmin({unit}: {unit: string}) {
  const [data, setData] = useState<GivingAdminPage | null>(null),
    [edit, setEdit] = useState<GivingAdminCard | null>(null),
    [amounts, setAmounts] = useState(''),
    [library, setLibrary] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const url = settingsUrl('/api/giving?' + new URLSearchParams({unit}));
  const load = useCallback(async () => {
    const r = await fetch(url, {cache: 'no-store'}).catch(() => null);
    const d = (r ? await r.json().catch(() => ({})) : {}) as GivingAdminPage & {error?: string};
    if (!r?.ok) setError(d.error || 'Sem conexão.');
    else setData(d);
  }, [url]);
  useEffect(() => {
    if (unit) void load();
  }, [load, unit]);
  async function act(action: string, payload: object, ok: string) {
    setBusy(true);
    setError('');
    setNotice('');
    const r = await fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action, data: payload})}).catch(
      () => null,
    );
    const d = (r ? await r.json().catch(() => ({})) : {}) as {error?: string};
    setBusy(false);
    if (!r?.ok) {
      setError(d.error || 'Sem conexão.');
      return false;
    }
    setNotice(ok);
    await load();
    return true;
  }
  function open(c: GivingAdminCard) {
    setEdit({...c, category: c.category || data?.categories[0]?.id || ''});
    setAmounts(givingAmountsText(c.amounts));
  }
  async function save() {
    if (!edit) return;
    const list = givingAmountsFromText(amounts);
    if (list === null) return setError('Valores sugeridos: use números separados por vírgula, de R$ 1 a R$ 100.000 (até 6).');
    if (await act('save', {...edit, amounts: list}, edit.version ? 'Cartão atualizado.' : 'Cartão criado. Ele já aparece no app, na aba Contribua.'))
      setEdit(null);
  }
  async function move(i: number, dir: -1 | 1) {
    if (!data) return;
    const ids = data.cards.map((c) => c.id),
      j = i + dir;
    if (j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j]!, ids[i]!];
    await act('reorder', {ids}, 'Ordem salva.');
  }
  if (!unit)
    return (
      <section className="program-card giving-admin">
        <p className="program-empty">Selecione uma igreja no topo para configurar a contribuição no app.</p>
      </section>
    );
  if (!data)
    return (
      <section className="program-card giving-admin">{error ? <p className="program-error">{error}</p> : <p className="program-empty">Carregando…</p>}</section>
    );
  return (
    <section className="program-card giving-admin">
      <div className="giving-head">
        <div>
          <p className="section-over">APLICATIVO DO MEMBRO</p>
          <h2>Contribua no app</h2>
          <p>Cartões que aparecem na aba Contribua. Personalize nome, frase, cor e imagem, e crie quantos quiser.</p>
        </div>
        <button type="button" className="program-primary" disabled={busy} onClick={() => open(blank())}>
          ＋ Novo cartão
        </button>
      </div>
      <div className={'giving-primary' + (data.primary ? '' : ' missing')}>
        {data.primary ? (
          <>
            <strong>Recebe pela conta principal</strong> · {data.primary.provider === 'mercado_pago' ? 'Mercado Pago' : data.primary.provider}
            {data.primary.holder ? ' · ' + data.primary.holder : ''} ·{' '}
            {data.primary.methods.map((m) => ({pix: 'Pix', card: 'Cartão', boleto: 'Boleto'})[m] || m).join(', ')}
          </>
        ) : (
          <>
            <strong>Nenhuma conta principal pronta.</strong> Em Financeiro › Contas recebedoras, marque uma conta de produção como principal. Sem ela, os
            cartões não aparecem no app.
          </>
        )}
      </div>
      {error && (
        <p className="program-error" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="program-notice" role="status">
          {notice}
        </p>
      )}
      {!data.cards.length && (
        <div className="giving-empty">
          <p>Nenhum cartão ainda. Comece pelos mais usados:</p>
          <div className="giving-suggestions">
            {givingSuggestions.map((s) => (
              <button type="button" key={s.title} disabled={busy} onClick={() => open({...blank(), ...s})}>
                ＋ {s.title}
              </button>
            ))}
          </div>
        </div>
      )}
      <div className="giving-grid">
        {data.cards.map((c, i) => (
          <article key={c.id} className={'giving-card-wrap' + (c.active ? '' : ' paused')}>
            <button type="button" className="giving-card" style={{['--g' as string]: c.color}} onClick={() => open(c)} aria-label={'Editar ' + c.title}>
              {c.image && <img src={c.image} alt="" referrerPolicy="no-referrer" />}
              <span className="giving-card-shade" />
              <span className="giving-card-text">
                <strong>{c.title}</strong>
                {c.subtitle && <small>{c.subtitle}</small>}
              </span>
            </button>
            <div className="giving-card-meta">
              <span className={c.ready ? 'ok' : 'warn'}>{!c.active ? 'Oculto' : c.ready ? 'No app' : 'Sem conta principal'}</span>
              <span className="giving-order">
                <button type="button" disabled={busy || i === 0} aria-label="Mover para a esquerda" onClick={() => void move(i, -1)}>
                  ‹
                </button>
                <button type="button" disabled={busy || i === data.cards.length - 1} aria-label="Mover para a direita" onClick={() => void move(i, 1)}>
                  ›
                </button>
              </span>
            </div>
          </article>
        ))}
      </div>
      {edit && (
        <div className="giving-editor" role="dialog" aria-label={edit.version ? 'Editar cartão' : 'Novo cartão'}>
          <div className="giving-editor-body">
            <div className="giving-preview">
              <div className="giving-card big" style={{['--g' as string]: edit.color}}>
                {edit.image && <img src={edit.image} alt="" referrerPolicy="no-referrer" />}
                <span className="giving-card-shade" />
                <span className="giving-card-text">
                  <strong>{edit.title || 'Nome do cartão'}</strong>
                  {edit.subtitle && <small>{edit.subtitle}</small>}
                </span>
              </div>
              <small>Prévia de como aparece no app.</small>
            </div>
            <div className="giving-fields">
              <h3>{edit.version ? 'Editar cartão' : 'Novo cartão'}</h3>
              <label>
                Nome
                <input
                  value={edit.title}
                  maxLength={40}
                  placeholder="Ex.: Dízimo, Oferta, Missões"
                  onChange={(e) => setEdit({...edit, title: e.target.value})}
                />
              </label>
              <label>
                Frase ou versículo (opcional)
                <input
                  value={edit.subtitle}
                  maxLength={160}
                  placeholder="Ex.: Cada um dê conforme determinou no coração"
                  onChange={(e) => setEdit({...edit, subtitle: e.target.value})}
                />
              </label>
              <div className="giving-colors" role="group" aria-label="Cor do cartão">
                {givingPresets.map((c) => (
                  <button
                    type="button"
                    key={c}
                    aria-pressed={edit.color === c}
                    style={{background: c}}
                    aria-label={'Cor ' + c}
                    onClick={() => setEdit({...edit, color: c})}
                  />
                ))}
                <label className="giving-color-custom">
                  Outra
                  <input type="color" value={edit.color} onChange={(e) => setEdit({...edit, color: e.target.value})} />
                </label>
              </div>
              <label>
                Imagem (opcional) · endereço HTTPS
                <input type="url" value={edit.image} maxLength={2000} placeholder="https://…" onChange={(e) => setEdit({...edit, image: e.target.value})} />
              </label>
              <div className="giving-row">
                <button type="button" onClick={() => setLibrary(true)}>
                  Escolher do banco de imagens
                </button>
                {edit.image && (
                  <button type="button" onClick={() => setEdit({...edit, image: ''})}>
                    Tirar imagem
                  </button>
                )}
              </div>
              {library && (
                <ImageLibrary
                  unit={unit}
                  close={() => setLibrary(false)}
                  pick={(img) => {
                    setLibrary(false);
                    setEdit((e) => (e ? {...e, image: location.origin + publishingImagePath(img.id)} : e));
                  }}
                />
              )}
              <label>
                Valores sugeridos em R$ (opcional)
                <input value={amounts} placeholder="Ex.: 20, 50, 100" onChange={(e) => setAmounts(e.target.value)} />
              </label>
              <label>
                Categoria de receita (financeiro)
                <select value={edit.category} onChange={(e) => setEdit({...edit, category: e.target.value})}>
                  <option value="">Selecione</option>
                  {data.categories.map((k) => (
                    <option key={k.id} value={k.id}>
                      {k.name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="program-check">
                <input type="checkbox" checked={edit.active} onChange={(e) => setEdit({...edit, active: e.target.checked})} />
                Mostrar no app
              </label>
              <div className="giving-row">
                <button type="button" className="program-primary" disabled={busy} onClick={() => void save()}>
                  {busy ? 'Salvando…' : 'Salvar cartão'}
                </button>
                {!!edit.version && (
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      window.confirm('Excluir o cartão ' + edit.title + '? As contribuições já feitas continuam no financeiro.') &&
                      void act('delete', {id: edit.id}, 'Cartão excluído.').then((ok) => ok && setEdit(null))
                    }
                  >
                    Excluir
                  </button>
                )}
                <button type="button" onClick={() => setEdit(null)}>
                  Cancelar
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
