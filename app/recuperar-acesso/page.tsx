'use client';
import {FormEvent,useState} from 'react';
import {createSupabaseBrowserClient,supabaseConfigured} from '../lib/supabase/client';
import {AuthCard} from '../AuthCard';

export default function RecoverAccess(){
 const[done,setDone]=useState(false),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 async function submit(event:FormEvent<HTMLFormElement>){
  event.preventDefault();setBusy(true);setError('');
  try{
   const body=new FormData(event.currentTarget);
   if(body.get('requestType')!=='access'){
    setError('Para alterar o e-mail, recuperar a dupla verificação ou revisar um bloqueio, fale com a equipe pelo atendimento Vinha. Esta tela não remove proteções da conta.');return;
   }
   if(!supabaseConfigured){setError('A recuperação está indisponível neste ambiente. Fale com a equipe Vinha.');return}
   const result=await createSupabaseBrowserClient().auth.resetPasswordForEmail(String(body.get('email')||'').trim(),{redirectTo:location.origin+'/conta/nova-senha'});
   if(result.error){setError('Não foi possível pedir o link agora. Aguarde alguns minutos e tente de novo.');return}
   setDone(true);
  }catch{setError('Não foi possível concluir. Verifique a conexão e tente de novo.')}
  finally{setBusy(false)}
 }
 if(done)return <AuthCard step="RECUPERAR ACESSO" title="Confira seu e-mail"><div className="auth-state"><i aria-hidden>✓</i>
  <p>Se o e-mail estiver cadastrado, você receberá o link para criar uma nova senha em alguns minutos. Confira também o spam. Este aviso não comprova a entrega do e-mail.</p>
  <a className="auth-primary" href="/login">Voltar para o login</a></div><div className="auth-links"><a href="/suporte">Preciso de atendimento</a></div></AuthCard>;
 return <AuthCard step="RECUPERAR ACESSO" title="Vamos recuperar seu acesso">
  <p>Informe o e-mail que você usa para entrar. Enviaremos um link para criar uma nova senha.</p>
  <form onSubmit={submit}>{error&&<p role="alert" className="auth-alert">{error}</p>}
   <label>E-mail de acesso<input type="email" name="email" autoComplete="email" maxLength={254} required placeholder="voce@exemplo.com"/></label>
   <label>O que aconteceu?<select name="requestType"><option value="access">Esqueci minha senha</option><option value="email_changed">Meu e-mail mudou</option><option value="mfa">Perdi a dupla verificação</option><option value="locked">Minha conta foi bloqueada</option></select></label>
   <button className="auth-primary" disabled={busy}>{busy?'Enviando…':'Enviar link'}</button>
  </form>
  <div className="auth-links"><a href="/login">← Voltar para o login</a><a href="/suporte">Falar com o suporte</a></div></AuthCard>;
}
