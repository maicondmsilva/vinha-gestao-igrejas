import {safeProrationNumber} from './proration-integer.ts';
type Row=Record<string,unknown>;
export function readProrationCatalog(value:unknown,planId:string){
 const object=(v:unknown):v is Row=>!!v&&typeof v==='object'&&!Array.isArray(v);
 if(!object(value)||!object(value.plan)||value.plan.id!==planId||!Array.isArray(value.modules)||!Array.isArray(value.links)||value.modules.length>1000||value.links.length>1000||JSON.stringify(value).length>131072)throw Error('Catálogo inválido.');
 safeProrationNumber(value.plan.base_price_cents);
 const codes=new Set<string>(),linked=new Set<string>();
 for(const m of value.modules){if(!object(m)||typeof m.code!=='string'||codes.has(m.code))throw Error('Módulo inválido.');safeProrationNumber(m.monthly_price_cents);codes.add(m.code)}
 for(const l of value.links){if(!object(l)||l.plan_id!==planId||typeof l.module_code!=='string'||!codes.has(l.module_code)||linked.has(l.module_code)||typeof l.included!=='boolean')throw Error('Vínculo inválido.');linked.add(l.module_code)}
 return value as {plan:Row;modules:Row[];links:Row[]};
}
export function prorationCatalogPrice(catalog:ReturnType<typeof readProrationCatalog>,decisions:Record<string,unknown>){
 const total=safeProrationNumber(catalog.plan.base_price_cents)+catalog.modules.filter(m=>decisions[String(m.code)]===true&&!catalog.links.some(l=>l.module_code===m.code&&l.included===true)).reduce((sum,m)=>sum+safeProrationNumber(m.monthly_price_cents),0);
 return safeProrationNumber(total);
}
