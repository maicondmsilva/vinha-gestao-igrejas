export type ImportRow={nome?:string;email?:string;telefone?:string;cpf?:string;nascimento?:string;status?:string;campus?:string;grupo?:string};
export type CheckedImportRow={line:number;row:Required<ImportRow>;errors:string[]};
const aliases:Record<string,string>={'nome completo':'nome','nome':'nome','e-mail':'email','email':'email','telefone':'telefone','celular':'telefone','cpf':'cpf','data de nascimento':'nascimento','nascimento':'nascimento','status':'status','campus':'campus','congregação':'campus','congregacao':'campus','grupo':'grupo','célula':'grupo','celula':'grupo'};
const statuses:Record<string,string>={'member':'Membro','membro':'Membro','visitor':'Visitante','visitante':'Visitante','integration':'Em integração','em integração':'Em integração'};
export function parseMemberCsv(source:string):ImportRow[]{
 // A small state machine supports quoted separators/newlines and escaped quotes.
 const records:string[][]=[];let row:string[]=[],field='',quoted=false;
 const text=source.replace(/^\uFEFF/,'');
 for(let i=0;i<text.length;i++){
  const char=text[i];
  if(char==='"'){if(quoted&&text[i+1]==='"'){field+='"';i++}else if(!field||quoted)quoted=!quoted;else throw new Error('Aspas inválidas na planilha.');}
  else if(char===';'&&!quoted){row.push(field.trim());field=''}
  else if((char==='\n'||char==='\r')&&!quoted){if(char==='\r'&&text[i+1]==='\n')i++;row.push(field.trim());if(row.some(Boolean))records.push(row);row=[];field=''}
  else field+=char;
 }
 if(quoted)throw new Error('Há um campo com aspas não fechadas.');
 row.push(field.trim());if(row.some(Boolean))records.push(row);
 if(!records.length)return[];
 const headers=records.shift()!.map(value=>aliases[value.toLocaleLowerCase('pt-BR')]);
 if(!headers.includes('nome')||headers.some(value=>!value)||new Set(headers).size!==headers.length)throw new Error('Use as colunas do modelo da Vinha, sem repetir cabeçalhos.');
 if(records.length>500)throw new Error('Importe no máximo 500 pessoas por arquivo.');
 return records.map(values=>{if(values.length!==headers.length)throw new Error('Há uma linha com quantidade de colunas diferente do cabeçalho.');return Object.fromEntries(headers.map((key,index)=>[key,values[index]]))});
}
export function normalizeBirthDate(value:string){
 if(!value)return'';
 let normalized=value;const br=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value);
 if(br)normalized=`${br[3]}-${br[2]}-${br[1]}`;
 if(!/^\d{4}-\d{2}-\d{2}$/.test(normalized))return null;
 const date=new Date(normalized+'T00:00:00Z');
 return !Number.isNaN(date.getTime())&&date.toISOString().slice(0,10)===normalized&&normalized<=new Date().toISOString().slice(0,10)?normalized:null;
}
export function validCpf(value:string){
 if(!/^\d{11}$/.test(value)||/^(\d)\1{10}$/.test(value))return false;
 for(let len=9;len<=10;len++){let sum=0;for(let i=0;i<len;i++)sum+=Number(value[i])*(len+1-i);let digit=(sum*10)%11;if(digit===10)digit=0;if(digit!==Number(value[len]))return false;}
 return true;
}
export function validateImportRows(value:unknown):CheckedImportRow[]{
 if(!Array.isArray(value)||!value.length||value.length>500)throw new Error('Envie entre 1 e 500 linhas por prévia.');
 const emails=new Set<string>(),cpfs=new Set<string>();
 return value.map((item,index)=>{
  const errors:string[]=[],source=item&&typeof item==='object'&&!Array.isArray(item)?item as Record<string,unknown>:{};
  if(item!==source||Object.keys(source).some(key=>!['nome','email','telefone','cpf','nascimento','status','campus','grupo'].includes(key)))errors.push('Colunas inválidas');
  const row:Required<ImportRow>={nome:'',email:'',telefone:'',cpf:'',nascimento:'',status:'Visitante',campus:'',grupo:''};
  for(const key of Object.keys(row) as (keyof ImportRow)[]){const raw=source[key];if(raw!==undefined&&typeof raw!=='string')errors.push('Campos devem ser texto');row[key]=typeof raw==='string'?raw.trim():key==='status'?'Visitante':'';}
  if(row.nome.length<2||row.nome.length>160)errors.push('Nome deve ter entre 2 e 160 caracteres');
  row.email=row.email.toLowerCase();if(row.email&&(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.email)||row.email.length>254))errors.push('E-mail inválido');
  if(row.email&&emails.has(row.email))errors.push('E-mail repetido na planilha');
  row.cpf=row.cpf.replace(/[.\-\s]/g,'');if(row.cpf&&!validCpf(row.cpf))errors.push('CPF inválido');
  if(row.cpf&&cpfs.has(row.cpf))errors.push('CPF repetido na planilha');
  const date=normalizeBirthDate(row.nascimento);if(date===null)errors.push('Data de nascimento inválida');else row.nascimento=date;
  row.status=statuses[row.status.toLowerCase()]||'';if(!row.status)errors.push('Status inválido');
  if(row.telefone.length>30||row.campus.length>160||row.grupo.length>160)errors.push('Campo excede o limite de caracteres');
  if(row.email)emails.add(row.email);if(row.cpf)cpfs.add(row.cpf);
  return{line:index+2,row,errors};
 });
}
