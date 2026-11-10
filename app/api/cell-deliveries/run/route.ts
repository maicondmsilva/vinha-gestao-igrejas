import {timingSafeEqual} from 'node:crypto';
import {NextResponse} from 'next/server';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {processCellExternalDeliveries} from '../../../lib/supabase/cell-deliveries';
export async function GET(r:Request){const secret=process.env.CELL_DELIVERY_CRON_SECRET,got=r.headers.get('authorization')||'';if(!secret||Buffer.byteLength(got)!==Buffer.byteLength('Bearer '+secret)||!timingSafeEqual(Buffer.from(got),Buffer.from('Bearer '+secret)))return NextResponse.json({error:'Rotina não autorizada.'},{status:401});try{return NextResponse.json(await processCellExternalDeliveries(supabaseAdminClient()),{headers:{'Cache-Control':'no-store'}})}catch{return NextResponse.json({error:'Não foi possível confirmar o processamento. Consulte os registros antes de repetir.'},{status:503})}}
