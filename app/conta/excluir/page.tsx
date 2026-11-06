'use client';
import {type FormEvent, useEffect, useState} from 'react';
import {createSupabaseBrowserClient, supabaseConfigured} from '../../lib/supabase/client';
import '../../access-flow.css';

/** Public account deletion page (Google Play "delete account" URL); the app has the same option in its menu. */
export default function AccountDeletionPage() {
  const [email, setEmail] = useState<string | null>(null),
    [ready, setReady] = useState(false),
    [confirm, setConfirm] = useState(''),
    [busy, setBusy] = useState(false),
    [done, setDone] = useState(false),
    [notice, setNotice] = useState('');
  useEffect(() => {
    if (!supabaseConfigured) return;
    createSupabaseBrowserClient()
      .auth.getUser()
      .then(({data}) => {
        setEmail(data.user?.email || null);
        setReady(true);
      })
      .catch(() => setReady(true));
  }, []);
  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy || confirm.trim().toUpperCase() !== 'EXCLUIR') return;
    setBusy(true);
    setNotice('');
    try {
      const r = await fetch('/api/account/close', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({confirm: 'EXCLUIR', via: 'web'}),
      });
      const d = (await r.json().catch(() => ({}))) as {ok?: boolean; error?: string};
      if (!r.ok || !d.ok) throw Error(d.error || 'Não foi possível excluir agora.');
      await createSupabaseBrowserClient().auth.signOut({scope: 'local'}).catch(() => undefined);
      setDone(true);
    } catch (x) {
      setNotice(x instanceof Error ? x.message : 'Falha de conexão.');
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="access-flow">
      <section className="access-flow-card">
        <div className="access-step">CONTA VINHA</div>
        <h1>Excluir minha conta</h1>
        {done ? (
          <p>Sua conta foi excluída e você saiu de todos os aparelhos. Obrigado por ter caminhado conosco.</p>
        ) : (
          <>
            <p>
              Ao excluir, seu login e o acesso pelo aplicativo da igreja são removidos, assim como os avisos no celular.
              Registros que a igreja precisa guardar por lei (contribuições, presença Kids e histórico) permanecem com a
              igreja; para pedir a remoção desses dados, fale com a secretaria.
            </p>
            {!ready ? (
              <p role="status">Verificando sua sessão…</p>
            ) : !email ? (
              <p>
                Entre na sua conta para continuar. <a href="/login?next=/conta/excluir">Entrar →</a>
              </p>
            ) : (
              <form onSubmit={submit}>
                <p>
                  Conta: <b>{email}</b>
                </p>
                {notice && <div className="access-flow-notice">{notice}</div>}
                <label>
                  Digite EXCLUIR para confirmar
                  <input value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="off" required />
                </label>
                <button className="access-primary" disabled={busy || confirm.trim().toUpperCase() !== 'EXCLUIR'}>
                  {busy ? 'Excluindo…' : 'Excluir minha conta'}
                </button>
              </form>
            )}
          </>
        )}
      </section>
    </main>
  );
}
