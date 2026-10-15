'use client';
import {useEffect,useState} from 'react';
export default function SupportDepartment({value,onChange}:{value:string;onChange:(value:string)=>void}){
 const[items,setItems]=useState<{id:string;name:string}[]>([]),[error,setError]=useState(false);
 useEffect(()=>{let active=true;fetch('/api/support-chat?departments=1',{cache:'no-store'}).then(async r=>{if(!r.ok)throw new Error();const data=await r.json<{departments:{id:string;name:string}[]}>();if(active)setItems(data.departments)}).catch(()=>{if(active)setError(true)});return()=>{active=false}},[]);
 return <label>Com qual setor deseja falar?<select name="departmentId" required value={value} onChange={e=>onChange(e.target.value)}><option value="">{error?'Setores indisponíveis. Tente novamente.':'Selecione um setor'}</option>{items.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label>
}
