'use client';
import {useEffect,useState,type FormEvent} from 'react';
type Entry={name:string;createdAt:string;size:number};
export default function MemberFiles({personId}:{personId:string}){
 const[items,setItems]=useState<Entry[]>([]),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[revision,setRevision]=useState(0);
 const tenant=typeof window==='undefined'?'':new URLSearchParams(location.search).get('tenant')||'';
 const url=(file?:string)=>'/api/member-files?'+new URLSearchParams({person:personId,...(tenant?{tenant}:{}),...(file?{file}:{})});
 useEffect(()=>{if(!personId)return;let current=true;fetch(url(),{cache:'no-store'}).then(async r=>{const data=await r.json() as {items?:Entry[];error?:string};if(!r.ok)throw Error(data.error||'Falha ao carregar arquivos.');if(current)setItems(data.items||[])}).catch(e=>{if(current)setNotice(e.message)});return()=>{current=false}},[personId,tenant,revision]);
 async function send(event:FormEvent<HTMLFormElement>){event.preventDefault();const form=new FormData(event.currentTarget);form.set('person',personId);setBusy(true);setNotice('');try{const response=await fetch(url(),{method:'POST',body:form});const data=await response.json() as {ok?:boolean;error?:string};if(!response.ok||data.ok!==true)throw Error(data.error||'Não foi possível confirmar o envio.');setRevision(x=>x+1);setNotice('Arquivo salvo no armazenamento privado.')}catch(e){setNotice(e instanceof Error?e.message:'Falha de conexão.')}finally{setBusy(false)}}
 return <section><h3>Arquivos privados</h3><p>PDF, PNG ou JPEG, até 4 MB. Downloads exigem acesso atual ao cadastro; os arquivos não são públicos.</p>{notice&&<p role="status">{notice}</p>}<form onSubmit={e=>void send(e)}><input type="file" name="file" required accept=".pdf,.png,.jpg,.jpeg" disabled={busy}/><button type="submit" disabled={busy||!personId}>{busy?'Enviando…':'Salvar arquivo'}</button></form>{items.map(item=><p key={item.name}><a href={url(item.name)}>{item.name}</a> · {Math.ceil(item.size/1024)} KB</p>)}<small>A lista exibe até 100 arquivos. A exclusão física não é disponibilizada ao cliente.</small></section>
}
