'use client';
import {useEffect, useState} from 'react';
import '../member-auth.css';

/** Destino do link "Confirmar meu e-mail" enviado ao membro que criou a conta pelo aplicativo da igreja. */
export default function AccountConfirmed() {
  const [error, setError] = useState('');
  useEffect(() => {
    const hash = new URLSearchParams(location.hash.slice(1)), query = new URLSearchParams(location.search);
    const e = hash.get('error_description') || query.get('error_description');
    if (e) setError(/expired|invalid/i.test(e) ? 'Este link expirou ou já foi usado.' : 'Não foi possível confirmar com este link.');
    if (location.hash) history.replaceState(null, '', location.pathname);
  }, []);
  return (
    <main className="ma">
      <section className="ma-card">
        <header className="ma-head"><span className="ma-logo">V</span><div><b>Vinha</b><small>Aplicativo da sua igreja</small></div></header>
        <div className="ma-body">
          {error ? (
            <>
              <p className="ma-over">Confirmação de e-mail</p>
              <h1>Vamos tentar de novo</h1>
              <p className="ma-alert">{error}</p>
              <p>Abra o aplicativo da sua igreja e toque em <b>Entrar</b> com seu e-mail e senha. Se o e-mail ainda não foi confirmado, crie a conta de novo com o mesmo e-mail para receber um link novo.</p>
            </>
          ) : (
            <>
              <span className="ma-ok" aria-hidden="true">✓</span>
              <p className="ma-over">Tudo certo</p>
              <h1>E-mail confirmado!</h1>
              <p>Agora é só voltar ao <b>aplicativo da sua igreja</b> e tocar em <b>Entrar</b> com o e-mail e a senha que você criou.</p>
              <p>Depois, abra <b>Menu › Meu perfil</b> para completar seu cadastro e enviar para a igreja.</p>
            </>
          )}
          <p className="ma-note">Você já pode fechar esta página.</p>
        </div>
      </section>
    </main>
  );
}
