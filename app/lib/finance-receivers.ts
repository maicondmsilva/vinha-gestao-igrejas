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
  common.push('version','credential','publicKey','webhookSecret');if(!Number.isSafeInteger(d.version)||Number(d.version)<0||typeof d.credential!=='string'||d.credential.length<20||d.credential.length>2000||/[\s\r\n]/.test(d.credential))throw Error('Informe a chave oficial do provedor e atualize a configuração.');
  for(const k of ['publicKey','webhookSecret'])if(d[k]!==undefined&&(typeof d[k]!=='string'||String(d[k]).length>2000||/\s/.test(String(d[k]))))throw Error('Revise as chaves adicionais.');
  if(d.provider!=='mercado_pago'&&(d.publicKey||d.webhookSecret))throw Error('Campos adicionais disponíveis somente para Mercado Pago.');
  if(d.webhookSecret&&String(d.webhookSecret).length<20)throw Error('Informe a assinatura secreta completa do webhook.');
  if(d.webhookSecret===d.credential||d.publicKey===d.credential)throw Error('Access Token, Public Key e assinatura do webhook são credenciais diferentes.');
  data={...data,version:d.version,credential:d.credential,publicKey:d.publicKey||'',webhookSecret:d.webhookSecret||''};
 }else if(action==='primary'){
  common.push('version','primary');if(!Number.isSafeInteger(d.version)||Number(d.version)<1||typeof d.primary!=='boolean')throw Error('Atualize a conta e confira a seleção principal.');data={...data,version:d.version,primary:d.primary};
 }else if(action==='validate'||action==='activate'){
  common.push('version');if(!Number.isSafeInteger(d.version)||Number(d.version)<1||provider!=='mercado_pago')throw Error('Atualize a conexão Mercado Pago.');data.version=d.version;
  if(action==='activate'){common.push('confirmed');if(d.confirmed!==true)throw Error('Confirme a ativação dos recebimentos.');data.confirmed=true;}
 }else if(['revoke','refresh','connect','open'].includes(action)){
  if(action==='revoke'||action==='refresh'){common.push('version');if(!Number.isSafeInteger(d.version)||Number(d.version)<1)throw Error('Atualize a conexão.');data.version=d.version}
 }else throw Error('Ação inválida.');
 if(Object.keys(d).some(k=>!common.includes(k)))throw Error('Campo não permitido.');return{action,unit,data,provider,environment};
}
export function receiverOpeningUrl(provider:ReceiverProvider,environment:ReceiverEnvironment){
 return provider==='mercado_pago'?'https://www.mercadopago.com.br/':provider==='asaas'?(environment==='sandbox'?'https://sandbox.asaas.com/':'https://www.asaas.com/'):'https://safe2pay.com.br/';
}
