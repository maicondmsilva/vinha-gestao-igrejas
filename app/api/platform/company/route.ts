import {centralRoute,one,rpc,requireValue,clean} from '../../../lib/supabase/operations';
import {httpsUrl,validCnpj,type CompanyProfile} from '../../../lib/supabase/financial-payloads';
export const GET=centralRoute(async(_request,client,session)=>{
 requireValue(['owner','admin'].includes(session.role),'Somente administradores podem consultar dados da Vinha.',403);
 return{company:await one(client,'saas_company_profile','id','true')};
});
export const PUT=centralRoute(async(request,client)=>{
 requireValue(request.headers.get('origin')===new URL(request.url).origin,'Origem inválida.',403);
 const d=await request.json<{profile:CompanyProfile;revision:number}>(),p=d.profile;
 requireValue(p&&clean(p.legalName)&&validCnpj(p.taxId)&&/^\S+@\S+\.\S+$/.test(p.email),'Informe razão social, CNPJ válido e e-mail da Vinha.');
 requireValue(!p.logoUrl||httpsUrl(p.logoUrl),'O logotipo deve usar HTTPS.');
 const profile:CompanyProfile={legalName:clean(p.legalName,160),taxId:clean(p.taxId).replace(/\D/g,''),email:clean(p.email,254),city:clean(p.city,100),state:clean(p.state,2).toUpperCase(),municipalRegistration:clean(p.municipalRegistration,60),logoUrl:clean(p.logoUrl,1000),serviceCode:clean(p.serviceCode,50),serviceName:clean(p.serviceName,160),description:clean(p.description,2000),taxes:p.taxes||{},fiscalReviewed:p.fiscalReviewed===true};
 requireValue(JSON.stringify(profile.taxes).length<=6000&&typeof profile.taxes==='object'&&!Array.isArray(profile.taxes),'Configuração de tributos inválida.');
 return{ok:true,revision:await rpc(client,'save_vinha_company',{p_profile:profile,p_revision:Number(d.revision)||0})};
});
