import {NextResponse} from 'next/server';
import {sessionFrom} from '../_auth';
import {db,one} from '../../lib/supabase/operations';
export async function GET(request:Request){try{const session=await sessionFrom(request);if(!session)return NextResponse.json({authenticated:false},{status:401});const client=db(request),[onboarding,church]=await Promise.all([one(client,'saas_onboarding_progress','organization_id',session.churchId),one(client,'organizations','id',session.churchId)]);return NextResponse.json({authenticated:true,user:session,church,onboarding:onboarding||{status:'not_started',current_step:'identity'}})}catch{return NextResponse.json({error:'Não foi possível validar o acesso.'},{status:503})}}
