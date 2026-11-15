'use client';
import {createClient} from '@supabase/supabase-js';
import {useEffect, useMemo, useState} from 'react';
import {visitorHeard, visitorError, visitorPhoneMask} from '../../../shared/visitors';
import '../../member-auth.css';

type Page = {found: boolean; church?: string; ministry?: string};

/** Cadastro rápido do visitante: aberto pelo QR Code na entrada da igreja, sem conta e sem aplicativo. */
export default function VisitorPage() {
  const [unit, setUnit] = useState(''),
    [page, setPage] = useState<Page | null>(null),
    [name, setName] = useState(''),
    [phone, setPhone] = useState(''),
    [email, setEmail] = useState(''),
    [firstTime, setFirstTime] = useState<boolean | null>(null),
    [heard, setHeard] = useState(''),
    [contact, setContact] = useState(true),
    [visit, setVisit] = useState(false),
    [prayer, setPrayer] = useState(''),
    [consent, setConsent] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [done, setDone] = useState('');
  const client = useMemo(() => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL,
      key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    return url && key ? createClient(url, key, {auth: {persistSession: false}}) : null;
  }, []);
  useEffect(() => {
    const id = decodeURIComponent(location.pathname.split('/').filter(Boolean).pop() || '');
    setUnit(id);
    if (!client || !/^[0-9a-f-]{36}$/i.test(id)) {
      setPage({found: false});
      return;
    }
    void client.rpc('visitor_page', {p_unit: id}).then(({data}) => setPage((data as Page) || {found: false}));
  }, [client]);
  async function send() {
    if (!client || busy) return;
    setError('');
    if (name.trim().split(/\s+/).length < 2) return setError('Digite seu nome e sobrenome.');
    if (phone.replace(/\D/g, '').length < 10) return setError('Digite seu WhatsApp com DDD.');
    if (!consent) return setError('Marque a autorização para a igreja guardar seus dados.');
    setBusy(true);
    const r = await client.rpc('visitor_checkin', {
      p_unit: unit,
      p_data: {name, phone, email, consent, contact, visit, prayer, ...(firstTime === null ? {} : {firstTime}), ...(heard ? {heard} : {})},
    });
    setBusy(false);
    if (r.error) return setError(visitorError(r.error.message));
    setDone(String((r.data as {firstName?: string})?.firstName || ''));
  }
  return (
    <main className="ma">
      <section className="ma-card">
        <header className="ma-head">
          <span className="ma-logo">V</span>
          <div>
            <b>{page?.church || 'Vinha'}</b>
            <small>{page?.ministry ? page.ministry + ' · ' : ''}Seja bem-vindo</small>
          </div>
        </header>
        <div className="ma-body">
          {!page && <p>Carregando…</p>}
          {page && !page.found && (
            <>
              <p className="ma-over">QR Code inválido</p>
              <h1>Igreja não encontrada</h1>
              <p className="ma-alert">Peça à recepção um QR Code atualizado.</p>
            </>
          )}
          {page?.found && done && (
            <>
              <span className="ma-ok" aria-hidden="true">
                ✓
              </span>
              <p className="ma-over">Cadastro recebido</p>
              <h1>Que alegria ter você aqui{done ? ', ' + done : ''}!</h1>
              <p>A equipe da igreja vai receber seus dados com carinho.{contact ? ' Em breve alguém fala com você pelo WhatsApp.' : ''}</p>
            </>
          )}
          {page?.found && !done && (
            <form
              style={{display: 'grid', gap: 12}}
              onSubmit={(e) => {
                e.preventDefault();
                void send();
              }}
            >
              <p className="ma-over">Visitante</p>
              <h1>Conte um pouco sobre você</h1>
              <label>
                Nome e sobrenome
                <input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" maxLength={120} />
              </label>
              <label>
                WhatsApp
                <input
                  value={phone}
                  onChange={(e) => setPhone(visitorPhoneMask(e.target.value))}
                  inputMode="tel"
                  autoComplete="tel"
                  placeholder="(11) 98888-7777"
                />
              </label>
              <label>
                E-mail (opcional)
                <input value={email} onChange={(e) => setEmail(e.target.value)} inputMode="email" autoComplete="email" maxLength={160} />
              </label>
              <fieldset className="ma-choices">
                <legend>É a sua primeira vez aqui?</legend>
                <button type="button" aria-pressed={firstTime === true} onClick={() => setFirstTime(true)}>
                  Sim
                </button>
                <button type="button" aria-pressed={firstTime === false} onClick={() => setFirstTime(false)}>
                  Já vim antes
                </button>
              </fieldset>
              <label>
                Como conheceu a igreja?
                <select value={heard} onChange={(e) => setHeard(e.target.value)}>
                  <option value="">Escolha (opcional)</option>
                  {visitorHeard.map(([k, l]) => (
                    <option key={k} value={k}>
                      {l}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Pedido de oração (opcional)
                <textarea value={prayer} onChange={(e) => setPrayer(e.target.value)} maxLength={500} rows={3} />
              </label>
              <label className="ma-check">
                <input type="checkbox" checked={contact} onChange={(e) => setContact(e.target.checked)} /> Quero receber contato da igreja pelo WhatsApp
              </label>
              <label className="ma-check">
                <input type="checkbox" checked={visit} onChange={(e) => setVisit(e.target.checked)} /> Gostaria de receber uma visita
              </label>
              <label className="ma-check">
                <input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)} /> Autorizo a igreja a guardar estes dados para me
                acompanhar, conforme a <a href="/privacidade">política de privacidade</a>.
              </label>
              {error && (
                <p className="ma-alert" role="alert">
                  {error}
                </p>
              )}
              <button type="submit" disabled={busy}>
                {busy ? 'Enviando…' : 'Enviar'}
              </button>
              <p className="ma-note">Leva menos de um minuto. Seus dados ficam só com a igreja.</p>
            </form>
          )}
        </div>
      </section>
    </main>
  );
}
