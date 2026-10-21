import {uuidPattern} from './private-files.ts';
export const receiverProviders=[['mercado_pago','Mercado Pago'],['asaas','Asaas'],['safe2pay','Safe2Pay']] as const;
export const receiverMethods=[['pix','Pix'],['boleto','Boleto'],['card','Cartão'],['recurring','Recorrência']] as const;
export type ReceiverProvider=typeof receiverProviders[number][0];
export type ReceiverEnvironment='sandbox'|'production';
export function receiverId(v:unknown){if(typeof v!=='string'||!uuidPattern.test(v))throw Error('Identificador inválido.');return v.toLowerCase()}
export function receiverEnvironment(v:unknown):ReceiverEnvironment{if(v!=='sandbox'&&v!=='production')throw Error('Escolha o ambiente.');return v}
export function receiverProvider(v:unknown):ReceiverProvider{if(!receiverProviders.some(([p])=>p===v))throw Error('Provedor inválido.');return v as ReceiverProvider}
export function receiverCommand(v:unknown){
 if(!v||typeof v!=='object'||Array.isArray(v))throw Error('Dados inválidos.');const d=v as Record<string,unknown>;
 const unit=receiverId(d.unit),provider=receiverProvider(d.provider),environment=receiverEnvironment(d.environment),action=String(d.action);
 const common=['action','unit','provider','environment'];let data:Record<string,unknown>={provider,environment};
 if(action==='configure'){
  common.push('version','account','units','methods','holderConfirmed');
  if(!Number.isSafeInteger(d.version)||Number(d.version)<1||d.holderConfirmed!==true||!Array.isArray(d.units)||d.units.length<1||d.units.length>100||!Array.isArray(d.methods)||d.methods.length<1||d.methods.length>4)throw Error('Confira titularidade, igrejas e métodos.');
  const units=d.units.map(receiverId),methods=d.methods.map(String);if(new Set(units).size!==units.length||new Set(methods).size!==methods.length||methods.some(m=>!receiverMethods.some(([k])=>k===m)))throw Error('Seleção inválida.');
  data={...data,version:d.version,account:receiverId(d.account),units,methods,holderConfirmed:true};
 }else if(action==='key'){
  common.push('version','credential');if(!Number.isSafeInteger(d.version)||Number(d.version)<0||typeof d.credential!=='string'||d.credential.length<20||d.credential.length>2000||/[\s\r\n]/.test(d.credential))throw Error('Informe a chave oficial do provedor e atualize a configuração.');data={...data,version:d.version,credential:d.credential};
 }else if(['revoke','refresh','connect','open'].includes(action)){
  if(action==='revoke'||action==='refresh'){common.push('version');if(!Number.isSafeInteger(d.version)||Number(d.version)<1)throw Error('Atualize a conexão.');data.version=d.version}
 }else throw Error('Ação inválida.');
 if(Object.keys(d).some(k=>!common.includes(k)))throw Error('Campo não permitido.');return{action,unit,data,provider,environment};
}
export function receiverOpeningUrl(provider:ReceiverProvider,environment:ReceiverEnvironment){
 return provider==='mercado_pago'?'https://www.mercadopago.com.br/':provider==='asaas'?(environment==='sandbox'?'https://sandbox.asaas.com/':'https://www.asaas.com/'):'https://safe2pay.com.br/';
}
