import {detectedFile,privateFileLimit,uuidPattern} from './private-files.ts';
/** Browser-side preflight is for usability; Storage policies and server repeat authorization. */
export async function validateFinanceAttachment(file:File){
 if(!(file instanceof File)||!file.size||file.size>privateFileLimit)throw Error('Selecione PDF, PNG ou JPEG de até 4 MB.');
 const kind=detectedFile(new Uint8Array(await file.slice(0,16).arrayBuffer()));
 if(!kind||file.type&&file.type!==kind.mime)throw Error('O conteúdo do comprovante precisa ser PDF, PNG ou JPEG válido.');
 return file;
}
export async function uploadFinanceAttachment(unitId:string,entryId:string,file:File,tenant='',transport:typeof fetch=fetch){
 if(!uuidPattern.test(unitId)||!uuidPattern.test(entryId))throw Error('Lançamento não confirmado para o anexo.');
 await validateFinanceAttachment(file);
 const query=new URLSearchParams({unitId,entryId});if(tenant)query.set('tenant',tenant);
 const body=new FormData();body.append('file',file);
 const response=await transport('/api/finance-f1/files?'+query,{method:'POST',body,signal:AbortSignal.timeout(20000)});
 const d=await response.json() as {error?:string;name?:string};
 if(!response.ok||typeof d.name!=='string'||!new RegExp('^'+uuidPattern.source.slice(1,-1)+'\\.(pdf|png|jpg)$','i').test(d.name))throw Error(d.error||'Anexo não confirmado. Consulte a lista antes de repetir.');
 return d.name;
}
