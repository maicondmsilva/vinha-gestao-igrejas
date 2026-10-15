'use client';
import {FormEvent,useState} from 'react';
import {createSupabaseBrowserClient,supabaseConfigured} from '../lib/supabase/client';
import '../access-flow.css';

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
   if(result.error){setError('Não foi possível solicitar a recuperação. Aguarde alguns minutos ou utilize o atendimento Vinha.');return}
   setDone(true);
  }catch{setError('Não foi possível concluir a solicitação. Verifique a conexão ou fale com a equipe Vinha.')}
  finally{setBusy(false)}
 }
 return <main className="access-flow"><section className="access-flow-card recovery-card">
  <a className="access-flow-brand" href="/"><i>V</i><span><b>Vinha</b><small>Central de acesso</small></span></a>
  {done?<div className="recovery-success"><i>✓</i><h1>Confira seu e-mail</h1><p>Se o endereço estiver cadastrado e o envio estiver disponível, você receberá um link seguro para criar uma nova senha. Confira também o spam. Este aviso não comprova a entrega do e-mail.</p><a className="access-primary" href="/login">Voltar para o login</a><p><a href="/suporte">Preciso de atendimento</a></p></div>:<>
   <div className="access-step">RECUPERAÇÃO SEGURA</div><h1>Vamos recuperar seu acesso</h1>
   <p>Por segurança, a Vinha não confirma publicamente se uma conta existe. A entrega do e-mail ainda precisa ser validada com a equipe durante o pré-lançamento.</p>
   {error&&<div role="alert" className="access-flow-notice">{error}</div>}
   <form onSubmit={submit}><label>E-mail de acesso<input type="email" name="email" autoComplete="email" maxLength={254} required placeholder="voce@exemplo.com"/></label>
    <label>O que aconteceu?<select name="requestType"><option value="access">Esqueci minha senha</option><option value="email_changed">Meu e-mail mudou</option><option value="mfa">Perdi a dupla verificação</option><option value="locked">Minha conta foi bloqueada</option></select></label>
    <button className="access-primary" disabled={busy}>{busy?'Solicitando…':'Solicitar recuperação'}</button>
   </form><footer><a href="/login">← Voltar para o login</a><a href="/suporte">Falar com o suporte</a></footer>
  </>}
 </section></main>;
}
