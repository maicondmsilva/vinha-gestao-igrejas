export function profileChanges(payload:Record<string,string>,baseline:Record<string,string>){return Object.entries(payload).map(([field,value])=>({field,value,before:baseline[field]||'',status:value===(baseline[field]||'')?'same':!value?'removed':!baseline[field]?'new':'changed'} as const))}
/** Tipo de perfil (etapa da pessoa na igreja), com o vocabulário do cadastro de Pessoas. */
export const profileJourneys=[['Membro','Membro'],['Em integração','Em integração'],['Visitante','Visitante']] as const;
