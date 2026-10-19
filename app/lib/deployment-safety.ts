type DeploymentEnvironment=Record<string,string|undefined>;
const productionProject='aoxibaaydfgffrdqtkva';
// This identifier is public configuration, not a credential.
export function assertDeploymentIsolation(env:DeploymentEnvironment){
 const preview=env.VERCEL_ENV==='preview'||env.NEXT_PUBLIC_VINHA_ENV==='test';
 if(!preview)return;
 if(env.NEXT_PUBLIC_VINHA_ENV!=='test')throw Error('Preview exige ambiente público test.');
 const raw=env.NEXT_PUBLIC_SUPABASE_URL;
 if(!raw)throw Error('Preview exige banco de homologação explícito.');
 let url:URL;try{url=new URL(raw)}catch{throw Error('Endereço de homologação inválido.')}
 if(url.hostname===`${productionProject}.supabase.co`||url.hostname===`${productionProject}.supabase.in`||url.username||url.password)throw Error('Preview não pode usar o banco principal.');
 // An allowlist prevents custom domains/proxies from disguising the production project.
 const expected=env.NEXT_PUBLIC_VINHA_TEST_PROJECT_REF;
 if(!expected||expected===productionProject||!/^[a-z]{20}$/.test(expected)||url.origin!==`https://${expected}.supabase.co`)throw Error('Projeto separado de homologação não confirmado.');
 if(env.VINHA_PROVIDER_MODE&&env.VINHA_PROVIDER_MODE!=='sandbox')throw Error('Preview não pode ativar provedores reais.');
}
