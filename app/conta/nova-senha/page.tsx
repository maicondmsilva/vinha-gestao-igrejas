'use client';
import {FormEvent,useState,useSyncExternalStore} from 'react';
import {createSupabaseBrowserClient,supabaseConfigured} from '../../lib/supabase/client';
import {AuthCard,ExpiredLink,PasswordFields,linkProblem,passwordReady} from '../../AuthCard';

export default function NewPassword(){
 const[password,setPassword]=useState(''),[confirmation,setConfirmation]=useState(''),[notice,setNotice]=useState(''),[state,setState]=useState<'form'|'expired'|'done'>('form'),[busy,setBusy]=useState(false);
 // Erro do link vem no endereço; só existe no navegador.
 const badLink=useSyncExternalStore(()=>()=>{},linkProblem,()=>'');
 async function submit(e:FormEvent){e.preventDefault();setNotice('');
  if(!passwordReady(password,confirmation)){setNotice('Confira as regras da senha abaixo.');return}
  setBusy(true);const {error}=await createSupabaseBrowserClient().auth.updateUser({password});setBusy(false);
  if(error){if(/session|expired|token|jwt/i.test(error.message))setState('expired');else setNotice('A senha não foi aceita. Use pelo menos 8 caracteres, misturando letras e números.');return}
  await createSupabaseBrowserClient().rpc('password_change_done').then(()=>undefined,()=>undefined);
  setState('done')}
 if(!supabaseConfigured)return <AuthCard step="NOVA SENHA" title="Indisponível neste ambiente"><p>Fale com a equipe Vinha.</p></AuthCard>;
 if(state==='expired'||(badLink&&state==='form'))return <AuthCard step="NOVA SENHA" title="Não foi possível usar este link"><ExpiredLink/></AuthCard>;
 if(state==='done')return <AuthCard step="NOVA SENHA" title="Senha alterada"><div className="auth-state"><i aria-hidden>✓</i><p>Pronto! Use a nova senha para entrar no aplicativo e no painel.</p><a className="auth-primary" href="/login">Entrar na Vinha</a></div></AuthCard>;
 return <AuthCard step="NOVA SENHA" title="Crie sua nova senha"><p>Ela vale para o aplicativo e para o painel.</p>
  <form onSubmit={submit}>{notice&&<p className="auth-alert" role="alert">{notice}</p>}<PasswordFields password={password} confirmation={confirmation} setPassword={setPassword} setConfirmation={setConfirmation}/>
   <button className="auth-primary" disabled={busy}>{busy?'Salvando…':'Salvar nova senha'}</button></form></AuthCard>;
}
