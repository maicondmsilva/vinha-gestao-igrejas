'use client';
import {useEffect,useState} from 'react';
import Link from 'next/link';
import {createSupabaseBrowserClient,supabaseConfigured} from '../../lib/supabase/client';
import '../../access-flow.css';

export default function ContinueAuth(){const[message,setMessage]=useState('Validando a segurança da sessão…');useEffect(()=>{if(!supabaseConfigured){location.replace('/acesso');return}const supabase=createSupabaseBrowserClient();supabase.auth.mfa.getAuthenticatorAssuranceLevel().then(({data,error})=>{if(error){setMessage('Não foi possível validar a sessão.');return}if(data.currentLevel==='aal1'&&data.nextLevel==='aal2'){location.replace('/conta/seguranca?challenge=1');return}location.replace('/acesso')})},[]);return <main className="access-flow"><section className="access-flow-card recovery-card"><span className="login-symbol">V</span><h1>Acesso protegido</h1><p>{message}</p><Link href="/login">Voltar ao login</Link></section></main>}
