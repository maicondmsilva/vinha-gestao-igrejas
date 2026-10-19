import type {summarizeProrationDocument} from './proration-documents';
type Document=ReturnType<typeof summarizeProrationDocument>;
export function parseProrationDocuments(value:unknown):Document[]{
 if(!value||typeof value!=='object'||!('pilot' in value)||value.pilot!==true||!('documents' in value)||!Array.isArray(value.documents)||value.documents.length>100)throw Error('Resposta não confirmada.');
 const ids=new Set<string>();
 return value.documents.map((item:unknown)=>{
  if(!item||typeof item!=='object')throw Error('Documento inválido.');
  const row=item as Record<string,unknown>,integer=(x:unknown):x is string=>typeof x==='string'&&/^\d{1,30}$/.test(x);
  if(typeof row.id!=='string'||!row.id||ids.has(row.id)||typeof row.createdAt!=='string'||!Number.isFinite(Date.parse(row.createdAt))||!['credit','additional_invoice'].includes(String(row.kind))||!integer(row.amountCents)||!integer(row.usedCents)||row.externalChargeCreated!==false)throw Error('Documento inválido.');
  if(row.kind==='credit'){
   if(!integer(row.remainingCents)||BigInt(row.usedCents)+BigInt(row.remainingCents)!==BigInt(row.amountCents))throw Error('Saldo não confirmado.');
  }else if(row.remainingCents!==null||row.usedCents!=='0')throw Error('Documento adicional inválido.');
  ids.add(row.id);
  return {id:row.id,createdAt:row.createdAt,kind:String(row.kind),amountCents:row.amountCents,usedCents:row.usedCents,remainingCents:row.remainingCents as string|null,externalChargeCreated:false};
 });
}
