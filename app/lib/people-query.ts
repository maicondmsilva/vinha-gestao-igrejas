export function peopleQuery(request:Request){
 const params=new URL(request.url).searchParams;
 const integer=(key:string,fallback:number,max:number)=>{const raw=params.get(key);if(raw===null)return fallback;if(!/^[1-9]\d*$/.test(raw))throw new Error('Página ou tamanho inválido.');const number=Number(raw);if(!Number.isSafeInteger(number)||number>max)throw new Error('Página ou tamanho fora do limite.');return number};
 const page=integer('page',1,10000),limit=integer('limit',25,100);
 const q=(params.get('q')||'').trim(),status=(params.get('status')||'').trim(),group=(params.get('group')||'').trim(),unitId=(params.get('unitId')||'').trim(),id=(params.get('id')||'').trim();
 if(q.length>100||group.length>160||status.length>40)throw new Error('Filtro muito longo.');
 if(status&&!['Membro','Em integração','Visitante'].includes(status))throw new Error('Status inválido.');
 const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
 if(unitId&&!uuid.test(unitId)||id&&!uuid.test(id))throw new Error('Identificador inválido.');
 return{page,limit,q,status,group,unitId,id,from:(page-1)*limit,to:page*limit-1};
}
export function peopleSearchFilter(value:string){
 // PostgREST quoted values protect commas/parentheses; LIKE wildcards are literal.
 const pattern='%'+value.replace(/\\/g,'\\\\').replace(/%/g,'\\%').replace(/_/g,'\\_')+'%';
 const quoted=JSON.stringify(pattern);
 return ['full_name','email','phone'].map(column=>`${column}.ilike.${quoted}`).join(',');
}
