// Same-origin browser requests retain the selected ministry even in separate tabs.
export function tenantHint(request:Request){
 const url=new URL(request.url),explicit=request.headers.get('x-vinha-tenant')||url.searchParams.get('tenant');
 if(explicit)return explicit;
 try{const referer=new URL(request.headers.get('referer')||'');return referer.origin===url.origin?referer.searchParams.get('tenant')||'':''}catch{return ''}
}
