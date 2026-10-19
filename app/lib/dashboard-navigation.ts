// A bad explicit scope must never silently become the headquarters.
export const unavailableDashboardUnit='00000000-0000-4000-8000-000000000000';
export function dashboardUnitHint(search:string){
 const p=new URLSearchParams(search),values=p.getAll('unidade');if(!values.length)return null;
 return values.length===1&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(values[0])?values[0].toLowerCase():unavailableDashboardUnit;
}
