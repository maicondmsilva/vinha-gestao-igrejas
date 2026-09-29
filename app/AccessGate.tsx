'use client';

import Link from 'next/link';
import {ReactNode, useEffect, useState} from 'react';
import './access-gate.css';

export default function AccessGate({children}:{children:ReactNode}){
  const [state,setState]=useState<'loading'|'allowed'|'denied'>('loading');
  useEffect(()=>{fetch('/api/session').then(response=>setState(response.ok?'allowed':'denied')).catch(()=>setState('denied'))},[]);
  if(state==='allowed')return children;
  return <main className="access-gate"><section><span className="access-gate-logo">V</span>{state==='loading'?<><h1>Validando seu acesso</h1><p>Aguarde enquanto confirmamos sua conta e as permissões da sua igreja.</p><i className="access-gate-spinner"/></>:<><small>ACESSO PROTEGIDO</small><h1>Conta ainda não autorizada</h1><p>Entre com o e-mail que recebeu o convite da igreja. Se você já entrou, peça ao administrador para ativar ou reenviar seu acesso.</p><div><Link href="/login">Voltar para o login</Link><a href="mailto:suporte@vinha.app">Falar com o suporte</a></div></>}</section></main>;
}
