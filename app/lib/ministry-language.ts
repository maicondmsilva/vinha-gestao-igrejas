export const languageDefaults={
 'celulas.visitantes':'Visitantes',
 inicio:'Visão geral',pessoas:'Pessoas',familias:'Famílias e termos',aplicativo:'Aplicativo do membro',kids:'Área Kids',igrejas:'Igrejas e unidades',usuarios:'Usuários e permissões',eventos:'Cultos e eventos',celulas:'Células',escalas:'Escalas',louvor:'Louvor',comunicacao:'Comunicação',transmissoes:'Transmissões',financeiro:'Financeiro',relatorios:'Relatórios',configuracoes:'Configurações',
 'celulas.geral':'Visão geral','celulas.singular':'célula','celulas.plural':'células','celulas.cadastro':'Cadastro','celulas.encontros':'Encontros','celulas.participantes':'Participantes','celulas.relatorios':'Relatórios','celulas.categorias':'Categorias','celulas.responsavel':'Responsável','celulas.local':'Local ou orientação',
} as const;
export type LanguageKey=keyof typeof languageDefaults;
export type LanguageLabels=Partial<Record<LanguageKey,string>>;
export function languageLabels(value:unknown):LanguageLabels{
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('invalid_language');
 const result:LanguageLabels={};
 for(const [key,label]of Object.entries(value)){
  if(!Object.hasOwn(languageDefaults,key)||typeof label!=='string'||label.trim().length<2||label.length>48||/[\x00-\x1f\x7f]/.test(label))throw Error('invalid_language');
  result[key as LanguageKey]=label.trim();
 }
 return result;
}
export function languageState(value:unknown){
 const v=value as {organizationId:string;labels:unknown;version:number;canManage:boolean};
 if(!v||typeof v.organizationId!=='string'||!/^[a-f0-9-]{36}$/i.test(v.organizationId)||!Number.isSafeInteger(v.version)||v.version<0||typeof v.canManage!=='boolean')throw Error('invalid_language');
 return {organizationId:v.organizationId,labels:languageLabels(v.labels),version:v.version,canManage:v.canManage};
}
export const cellSections=['geral','cadastro','encontros','participantes','visitantes','relatorios','categorias'] as const;
export type CellSection=typeof cellSections[number];
export function cellSection(value:string|null):CellSection{return cellSections.includes(value as CellSection)?value as CellSection:'geral'}
