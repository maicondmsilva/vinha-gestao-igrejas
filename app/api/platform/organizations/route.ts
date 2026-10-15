import {NextResponse} from 'next/server';
import type {OperationsClient} from '../../../lib/supabase/operations';
import {platformSessionFrom} from '../../_auth';
import {createSupabaseRequestClient} from '../../../lib/supabase/request';

type UntypedClient=OperationsClient;
const client=(request:Request)=>createSupabaseRequestClient(request) as unknown as UntypedClient;
const activationOrigin=(request:Request)=>process.env.NEXT_PUBLIC_APP_URL||new URL(request.url).origin.replace('://central.','://app.');
const message=(error:string)=>error.includes('invalid_plan')?'Plano inválido.':error.includes('organization_not_found')?'Organização não encontrada.':error.includes('invite_not_found')?'Responsável não encontrado.':error.includes('duplicate key')?'Já existe um cadastro com estes dados.':'Não foi possível concluir a operação.';

export async function GET(request:Request){
 if(!await platformSessionFrom(request))return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const supabase=client(request),[overview,plans]=await Promise.all([
  supabase.rpc('platform_organizations_overview'),
  supabase.from('saas_plans').select('id,code,name,description,base_price_cents,active').eq('active',true).order('base_price_cents'),
 ]);
 const profiles=await supabase.from('saas_billing_profiles').select('church_id'),registrations=await supabase.from('saas_trial_registrations').select('organization_id,full_name,email');
 const error=overview.error||plans.error||profiles.error||registrations.error;
 if(error)return NextResponse.json({error:message(error.message)},{status:400});
 return NextResponse.json({organizations:(overview.data||[]).map((organization:{id:string})=>({...organization,registration_source:(registrations.data||[]).some(r=>r.organization_id===organization.id)?'website':'central',owner_name:(registrations.data||[]).find(r=>r.organization_id===organization.id)?.full_name||(organization as {owner_name?:string}).owner_name,owner_email:(registrations.data||[]).find(r=>r.organization_id===organization.id)?.email||(organization as {owner_email?:string}).owner_email,billing_profile_complete:(profiles.data||[]).some(profile=>profile.church_id===organization.id)})),plans:plans.data||[]});
}

export async function POST(request:Request){
 if(!await platformSessionFrom(request))return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const d=await request.json<Record<string,unknown>>(),name=String(d.name||'').trim(),ownerEmail=String(d.ownerEmail||'').trim().toLowerCase(),ownerName=String(d.ownerName||'').trim();
 if(!name||!ownerName||!String(d.seniorPastorName||'').trim()||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(ownerEmail))return NextResponse.json({error:'Informe ministério, pastor titular, responsável e e-mail válido.'},{status:400});
 const supabase=client(request),result=await supabase.rpc('create_platform_organization',{p_name:name,p_owner_name:ownerName,p_owner_email:ownerEmail,p_plan_id:String(d.planId||'plan-essential'),p_app_addon:Boolean(d.appAddon),p_app_name:String(d.appName||name),p_primary_color:String(d.primaryColor||'#285c45'),p_senior_pastor_name:String(d.seniorPastorName||'')});
 if(result.error)return NextResponse.json({error:message(result.error.message)},{status:400});
 const created=result.data as {id:string;slug:string;trial_ends_at:string;invite_token:string};
 return NextResponse.json({id:created.id,slug:created.slug,trialEndsAt:created.trial_ends_at,activationUrl:`${activationOrigin(request)}/ativar/${created.invite_token}`},{status:201});
}

export async function PATCH(request:Request){
 if(!await platformSessionFrom(request))return NextResponse.json({error:'Acesso exclusivo da administração Vinha.'},{status:403});
 const d=await request.json<Record<string,unknown>>(),id=String(d.id||'');
 if(!id)return NextResponse.json({error:'Organização inválida.'},{status:400});
 const supabase=client(request);
 if(d.action==='regenerate_invite'){
  const result=await supabase.rpc('regenerate_platform_organization_invite',{p_organization_id:id});
  if(result.error)return NextResponse.json({error:message(result.error.message)},{status:400});
  return NextResponse.json({ok:true,activationUrl:`${activationOrigin(request)}/ativar/${result.data}`});
 }
 const patch={...d};delete patch.id;delete patch.action;
 const result=await supabase.rpc('update_platform_organization',{p_organization_id:id,p_patch:patch});
 if(result.error)return NextResponse.json({error:message(result.error.message)},{status:400});
 return NextResponse.json({ok:true});
}
