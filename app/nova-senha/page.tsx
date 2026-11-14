'use client';
import {createClient, type SupabaseClient} from '@supabase/supabase-js';
import {useEffect, useState, type FormEvent} from 'react';
import '../member-auth.css';

/** Destino do link "Criar nova senha" pedido no aplicativo da igreja (o link traz a sessão temporária no endereço). */
export default function NewPassword() {
  const [client, setClient] = useState<SupabaseClient | null>(null);
  const [state, setState] = useState<'loading' | 'form' | 'done' | 'invalid'>('loading');
  const [password, setPassword] = useState(''), [confirm, setConfirm] = useState(''), [error, setError] = useState(''), [busy, setBusy] = useState(false);
  useEffect(() => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !key) { setState('invalid'); return; }
    const c = createClient(url, key, {auth: {flowType: 'implicit', detectSessionInUrl: true, persistSession: false}});
    setClient(c);
    if (/error_description/.test(location.hash)) { setState('invalid'); return; }
    c.auth.getSession().then(({data}) => {
      setState(data.session ? 'form' : 'invalid');
      if (location.hash) history.replaceState(null, '', location.pathname);
    });
  }, []);
  async function save(e: FormEvent) {
    e.preventDefault(); setError('');
    if (password.length < 8) { setError('A senha precisa ter pelo menos 8 caracteres.'); return; }
    if (password !== confirm) { setError('As duas senhas precisam ser iguais.'); return; }
    setBusy(true);
    const r = await client!.auth.updateUser({password});
    setBusy(false);
    if (r.error) { setError('Não foi possível salvar. Peça um novo link no aplicativo.'); return; }
    await client!.auth.signOut();
    setState('done');
  }
  return (
    <main className="ma">
      <section className="ma-card">
        <header className="ma-head"><span className="ma-logo">V</span><div><b>Vinha</b><small>Aplicativo da sua igreja</small></div></header>
        <div className="ma-body">
          <p className="ma-over">Recuperar acesso</p>
          {state === 'loading' && <p>Conferindo o link…</p>}
          {state === 'invalid' && (<><h1>Link expirado</h1><p className="ma-alert">Este link já foi usado ou passou do prazo de 1 hora.</p><p>No aplicativo da sua igreja, digite seu e-mail e toque em <b>Esqueci minha senha</b> para receber um link novo.</p></>)}
          {state === 'done' && (<><span className="ma-ok" aria-hidden="true">✓</span><h1>Senha nova salva!</h1><p>Volte ao aplicativo da sua igreja e entre com o seu e-mail e a senha nova.</p></>)}
          {state === 'form' && (
            <form onSubmit={save} style={{display: 'grid', gap: 12}}>
              <h1>Crie sua nova senha</h1>
              <label>Nova senha<input type="password" autoComplete="new-password" minLength={8} value={password} onChange={(e) => setPassword(e.target.value)} /></label>
              <label>Repita a nova senha<input type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} /></label>
              {error && <p className="ma-alert" role="alert">{error}</p>}
              <button type="submit" disabled={busy}>{busy ? 'Salvando…' : 'Salvar nova senha'}</button>
            </form>
          )}
        </div>
      </section>
    </main>
  );
}
