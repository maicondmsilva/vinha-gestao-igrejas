export function settingsUrl(path='/api/organization-settings'){
 const url=new URL(path,location.origin),tenant=new URLSearchParams(location.search).get('tenant');if(tenant)url.searchParams.set('tenant',tenant);return url.pathname+url.search;
}
