import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import { sessionFrom } from '../_auth';
export async function GET(request:Request){const session=await sessionFrom(request);if(!session)return NextResponse.json({authenticated:false},{status:401});const onboarding=await env.DB.prepare('SELECT status,current_step FROM saas_onboarding_progress WHERE church_id=?').bind(session.churchId).first<{status:string;current_step:string}>();return NextResponse.json({authenticated:true,user:session,onboarding:onboarding||null})}
