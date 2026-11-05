export type CommerceMode='event'|'sale';
export type CommerceInput={mode:CommerceMode;pickupLocal:string;receiver:string;methods:string[]};
export type CommerceReceiver={id:string;name:string;unit:string;unit_name:string;provider:string;primary:boolean;methods:string[];canConfigure:boolean};
export function commerceInputValid(v:unknown):v is CommerceInput{
 if(!v||typeof v!=='object'||Array.isArray(v))return false;const d=v as Record<string,unknown>;
 return Object.keys(d).sort().join(',')==='methods,mode,pickupLocal,receiver'&&['event','sale'].includes(String(d.mode))&&typeof d.pickupLocal==='string'&&(d.mode==='event'?d.pickupLocal==='':/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(d.pickupLocal))&&typeof d.receiver==='string'&&(d.receiver===''||/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(d.receiver))&&Array.isArray(d.methods)&&d.methods.length<=3&&new Set(d.methods).size===d.methods.length&&d.methods.every(m=>['pix','card','boleto'].includes(m))&&(!d.receiver||d.methods.length>0);
}
export function productLabel(name:string,size:string,color:string){return[name,size,color].map(x=>x.trim()).filter(Boolean).join(' · ')}
