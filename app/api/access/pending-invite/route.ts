import {NextResponse} from 'next/server';
import {db,rpc} from '../../../lib/supabase/operations';
export async function GET(request:Request){try{const client=db(request),{data:{user}}=await client.auth.getUser();if(!user)return NextResponse.json({error:'Autenticação necessária.'},{status:401});return NextResponse.json({invite:await rpc(client,'pending_organization_invitation')},{headers:{'Cache-Control':'no-store'}})}catch{return NextResponse.json({error:'Não foi possível verificar seu convite.'},{status:503})}}
