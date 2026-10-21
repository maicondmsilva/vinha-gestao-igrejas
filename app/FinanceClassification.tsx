'use client';
import {useState} from 'react';
import type {Catalog} from './FinanceModule';
export function financeClassification(catalog:Catalog[],id?:string|null){const c=catalog.find(c=>c.id===id);return{category:c?.parent_id?catalog.find(p=>p.id===c.parent_id)?.name||'Categoria anterior':c?.name||'—',subcategory:c?.parent_id?c.name:''}}
export default function FinanceClassification({catalog,direction,required=true,prefix=''}:{catalog:Catalog[];direction:string;required?:boolean;prefix?:string}){
 const [root,setRoot]=useState(''),[child,setChild]=useState('');
 const items=catalog.filter(c=>c.active&&c.kind==='category'&&c.direction===direction),children=items.filter(c=>c.parent_id===root);
 return <div className="f1-form-grid wide f2-classification"><label>Categoria<select name={prefix+'primaryCategory'} value={root} required={required} onChange={e=>{setRoot(e.target.value);setChild('')}}><option value="">Selecione a categoria</option>{items.filter(c=>!c.parent_id).map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label><label>Subcategoria · opcional<select name={prefix+'subcategory'} value={child} disabled={!root||!children.length} onChange={e=>setChild(e.target.value)}><option value="">{!root?'Escolha a categoria primeiro':children.length?'Sem subcategoria':'Nenhuma subcategoria cadastrada'}</option>{children.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label><input type="hidden" name={prefix+'category'} value={child||root}/></div>;
}
