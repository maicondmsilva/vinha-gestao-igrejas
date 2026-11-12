'use client';
import {FormEvent,useState} from 'react';
import {createSupabaseBrowserClient,supabaseConfigured} from '../../lib/supabase/client';
import {AuthCard,PasswordFields,passwordReady} from '../../AuthCard';
import {safeNext} from '../../lib/navigation';

/** Primeiro acesso de um usuário criado pelo painel: a senha recebida da igreja precisa ser trocada. */
export default function ChangePassword(){
 const[password,setPassword]=useState(''),[confirmation,setConfirmation]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false);
 async function submit(e:FormEvent){e.preventDefault();setNotice('');
  if(!passwordReady(password,confirmation)){setNotice('Confira as regras da senha abaixo.');return}
  setBusy(true);try{const client=createSupabaseBrowserClient();
   const {error}=await client.auth.updateUser({password});
   if(error){setNotice(/same|different/i.test(error.message)?'Escolha uma senha diferente da que você recebeu.':/session|jwt/i.test(error.message)?'Sua sessão terminou. Entre de novo com a senha recebida.':'A senha não foi aceita. Use pelo menos 8 caracteres, misturando letras e números.');return}
   const done=await client.rpc('password_change_done');if(done.error){setNotice('Senha alterada, mas não conseguimos confirmar. Tente de novo.');return}
   location.assign('/auth/continuar?next='+encodeURIComponent(safeNext(new URLSearchParams(location.search).get('next'))));
  }catch{setNotice('Falha de conexão. Tente de novo.')}finally{setBusy(false)}}
 if(!supabaseConfigured)return <AuthCard step="PRIMEIRO ACESSO" title="Indisponível neste ambiente"><p>Fale com a equipe Vinha.</p></AuthCard>;
 return <AuthCard step="PRIMEIRO ACESSO" title="Crie sua senha pessoal"><p>Você entrou com a senha que a igreja cadastrou. Para continuar, escolha uma senha só sua. Ela vale para o aplicativo e para o painel.</p>
  <form onSubmit={submit}>{notice&&<p className="auth-alert" role="alert">{notice}</p>}<PasswordFields password={password} confirmation={confirmation} setPassword={setPassword} setConfirmation={setConfirmation}/>
   <button className="auth-primary" disabled={busy}>{busy?'Salvando…':'Salvar e continuar'}</button></form>
  <div className="auth-links"><a href="/login">Sair</a></div></AuthCard>;
}
