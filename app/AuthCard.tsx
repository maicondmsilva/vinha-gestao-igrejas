'use client';
import {useState,type ReactNode} from 'react';
import './auth-screens.css';

/** Cartão central das telas de acesso (recuperar, nova senha e troca obrigatória), com a marca Vinha. */
export function AuthCard({step,title,children}:{step:string;title:string;children:ReactNode}){
 return <main className="auth-screen"><section className="auth-card">
  {/* eslint-disable-next-line @next/next/no-html-link-for-pages -- o projeto não usa next/link (ver access-security.test) */}
  <a className="auth-brand" href="/"><i aria-hidden>V</i><span><b>Vinha</b><small>Gestão que frutifica</small></span></a>
  <div className="auth-body"><p className="auth-step">{step}</p><h1>{title}</h1>{children}</div>
  <footer className="auth-foot">A Vinha nunca pede sua senha por chat ou telefone.</footer>
 </section></main>;
}

/** Senha e confirmação com as regras visíveis enquanto a pessoa digita. */
export function PasswordFields({password,confirmation,setPassword,setConfirmation}:{password:string;confirmation:string;setPassword:(v:string)=>void;setConfirmation:(v:string)=>void}){
 const[show,setShow]=useState(false),longEnough=password.length>=8,same=!!password&&password===confirmation;
 return <>
  <label>Nova senha<span className="auth-pass"><input type={show?'text':'password'} value={password} onChange={e=>setPassword(e.target.value)} minLength={8} maxLength={72} required autoComplete="new-password"/>
   <button type="button" onClick={()=>setShow(v=>!v)} aria-pressed={show}>{show?'Ocultar senha':'Mostrar senha'}</button></span></label>
  <label>Confirmar nova senha<input type={show?'text':'password'} value={confirmation} onChange={e=>setConfirmation(e.target.value)} minLength={8} maxLength={72} required autoComplete="new-password"/></label>
  <ul className="auth-rules" aria-live="polite"><li className={longEnough?'ok':''}>{longEnough?'✓':'•'} Mínimo de 8 caracteres</li><li className={same?'ok':''}>{same?'✓':'•'} As duas senhas são iguais</li></ul>
 </>;
}
export const passwordReady=(p:string,c:string)=>p.length>=8&&p===c;

/** Lê o erro que o Supabase devolve no endereço quando o link de recuperação venceu ou já foi usado. */
export function linkProblem():string{
 if(typeof window==='undefined')return '';
 const params=new URLSearchParams(location.hash.replace(/^#/,'')+'&'+location.search.replace(/^\?/,''));
 const code=params.get('error_code')||'',error=params.get('error')||'';
 // otp_expired (vencido ou já usado), access_denied e outros: todos pedem um link novo.
 return code||error?'expired':'';
}

export function ExpiredLink(){
 return <div className="auth-state"><i aria-hidden className="warn">!</i><h2>Link vencido</h2><p>Este link de recuperação já foi usado ou passou do prazo. Peça um novo link: ele chega no seu e-mail em alguns minutos.</p><a className="auth-primary" href="/recuperar-acesso">Pedir novo link</a></div>;
}
