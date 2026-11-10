'use client';
import {useState} from 'react';
import {createSupabaseBrowserClient} from './lib/supabase/client';
export default function SignOutButton(){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 async function leave(){if(busy)return;setBusy(true);setError('');try{const {error}=await createSupabaseBrowserClient().auth.signOut({scope:'local'});if(error)throw error;for(const key of Object.keys(sessionStorage))if(key.startsWith('vinha:'))sessionStorage.removeItem(key);location.replace('/login')}catch{setError('Não foi possível encerrar a sessão. Tente novamente.');setBusy(false)}}
 return <div className="sidebar-signout"><button type="button" disabled={busy} onClick={()=>void leave()} aria-label="Sair da plataforma">↪ {busy?'Saindo…':'Sair da plataforma'}</button>{error&&<small role="alert">{error}</small>}</div>;
}
