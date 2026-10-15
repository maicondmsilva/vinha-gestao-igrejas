'use client';

import {createSupabaseBrowserClient} from './lib/supabase/client';
import {ReactNode, useEffect, useState} from 'react';
import './access-gate.css';

export default function AccessGate({children}:{children:ReactNode}){
  const [state,setState]=useState<'loading'|'allowed'|'denied'>('loading');
  useEffect(()=>{const query=new URLSearchParams(location.search),tenant=query.get('tenant');createSupabaseBrowserClient().auth.getUser().then(()=>fetch('/api/session'+(tenant?`?tenant=${encodeURIComponent(tenant)}`:''))).then(async response=>{if(response.status===401){location.replace('/login?next='+encodeURIComponent(location.pathname+location.search));return}if(!response.ok){setState('denied');return}const data=await response.json();if(data.onboarding&&data.onboarding.status!=='completed'){const tenant=data.user?.churchSlug?`?tenant=${encodeURIComponent(data.user.churchSlug)}`:'';location.replace(`/onboarding${tenant}`);return}setState('allowed')}).catch(()=>setState('denied'))},[]);
  if(state==='allowed')return children;
  return <main className="access-gate"><section><span className="access-gate-logo">V</span>{state==='loading'?<><h1>Validando seu acesso</h1><p>Aguarde enquanto confirmamos sua conta e as permissões da sua igreja.</p><i className="access-gate-spinner"/></>:<><small>ACESSO PROTEGIDO</small><h1>Conta ainda não autorizada</h1><p>Entre com o e-mail que recebeu o convite da igreja. Se você já entrou, peça ao administrador para ativar ou reenviar seu acesso.</p><div><a href="/login">Voltar para o login</a><a href="/suporte">Falar com o suporte</a></div></>}</section></main>;
}
