'use client';
import {useEffect,useState} from 'react';
import './action-coordinator.css';

type ActionDetail={label?:string};

const destinations:[RegExp,string][]=[
  [/painel/i,'inicio'],
  [/transmiss/i,'transmissoes'],
  [/escala/i,'escalas'],
  [/evento|programaç/i,'eventos'],
  [/canal|comunicaç/i,'comunicacao'],
  [/família/i,'familias'],
  [/sala/i,'kids'],
  [/logo|vídeo|modelo|configuraç/i,'configuracoes']
];

export default function ActionCoordinator(){
 const[action,setAction]=useState('');
 useEffect(()=>{
  const open=(labelValue:string)=>{
    const label=String(labelValue||'Ação');
    const route=destinations.find(([pattern])=>pattern.test(label));
    if(route && new URLSearchParams(location.search).get('pagina')!==route[1]){
      const url=new URL('/painel',location.origin);
      url.searchParams.set('pagina',route[1]);
      location.assign(url);
      return;
    }
    setAction(label);
  };

  const listener=(event:Event)=>open(String((event as CustomEvent<ActionDetail>).detail?.label||'Ação'));

  const buttonFallback=(event:MouseEvent)=>{
    if(event.defaultPrevented)return;
    const button=(event.target as Element|null)?.closest('button') as HTMLButtonElement|null;
    if(!button||!button.isConnected||button.disabled||button.getAttribute('aria-current'))return;
    const reactKey=Object.keys(button).find(key=>key.startsWith('__reactProps$'));
    const props=reactKey?(button as unknown as Record<string,unknown>)[reactKey] as {onClick?:unknown;formAction?:unknown}:undefined;
    if(typeof props?.onClick==='function'||props?.formAction)return;
    if(button.form&&(button.type==='submit'||!button.getAttribute('type')))return;
    open((button.textContent||button.getAttribute('aria-label')||'Ação').replace(/\s+/g,' ').trim());
  };

  window.addEventListener('vinha:action',listener);
  document.addEventListener('click',buttonFallback);
  return()=>{window.removeEventListener('vinha:action',listener);document.removeEventListener('click',buttonFallback)}
 },[]);

 if(!action)return null;
 return <div className="action-overlay" role="presentation" onClick={()=>setAction('')}><section className="action-dialog" role="dialog" aria-modal="true" aria-labelledby="action-title" onClick={e=>e.stopPropagation()}><button className="action-close" aria-label="Fechar" onClick={()=>setAction('')}>×</button><small>CENTRAL DE AÇÕES</small><h2 id="action-title">{action}</h2><p>Este controle foi identificado na revisão de interações, mas a operação específica ainda não está concluída. Ele não ficará mais silencioso: a Vinha agora informa o estado e impede que a equipe suponha que uma alteração foi salva.</p><div className="action-warning"><b>Ação não executada</b><span>Nenhum dado foi alterado. A implementação funcional deste comando permanece no inventário de correções.</span></div><footer><button onClick={()=>setAction('')}>Entendi</button></footer></section></div>
}
