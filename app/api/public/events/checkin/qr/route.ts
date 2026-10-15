import { withLegacyContainment } from '../../../../../lib/release-availability';
import { env } from 'cloudflare:workers';
import { NextResponse } from 'next/server';
import QRCode from 'qrcode';

async function legacyGET(request:Request){const token=(new URL(request.url).searchParams.get('token')||'').toLowerCase();if(!token)return NextResponse.json({error:'Código não informado.'},{status:400});const registration=await env.DB.prepare('SELECT id FROM event_registrations WHERE checkin_token=?').bind(token).first();if(!registration)return NextResponse.json({error:'Inscrição não encontrada.'},{status:404});const svg=await QRCode.toString(token,{type:'svg',margin:1,width:240,color:{dark:'#173d2d',light:'#ffffff'}});return new NextResponse(svg,{headers:{'Content-Type':'image/svg+xml; charset=utf-8','Cache-Control':'private, no-store','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'"}})}

export const GET = withLegacyContainment(legacyGET);
