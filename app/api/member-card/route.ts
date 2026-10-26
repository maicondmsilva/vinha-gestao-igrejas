import {createClient} from '@supabase/supabase-js';
import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import QRCode from 'qrcode';
import {db} from '../../lib/supabase/operations';
import {boundedBody,uuidPattern} from '../../lib/private-files';
import {trustedSessionRequest} from '../../lib/access-security';
import type {DigitalCard} from '../../../shared/member-services';
export async function POST(request:Request){try{
 const token=request.headers.get('authorization');if(!token&&!trustedSessionRequest(request))return new Response(null,{status:403});
 if(token&&!/^Bearer [A-Za-z0-9_.-]+$/.test(token))return new Response(null,{status:401});
 const client=token?createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,{global:{headers:{Authorization:token}},auth:{persistSession:false,autoRefreshToken:false}}):db(request);
 const b=JSON.parse(new TextDecoder().decode(await boundedBody(request,1000)));if(!b||![b.org,b.unit,b.id].every(x=>typeof x==='string'&&uuidPattern.test(x)))return new Response(null,{status:400});
 const r=await client.rpc('member_services',{p_org:b.org,p_unit:b.unit,p_action:'cards'});if(r.error)return new Response(null,{status:403});const card=(r.data.items as DigitalCard[]).find(c=>c.id===b.id&&c.valid&&c.code);if(!card)return new Response(null,{status:404});
 const doc=await PDFDocument.create(),page=doc.addPage([540,340]),font=await doc.embedFont(StandardFonts.Helvetica),bold=await doc.embedFont(StandardFonts.HelveticaBold);
 const color=/^#[0-9a-f]{6}$/i.test(card.primary||'')?card.primary!:'#0b4635';page.drawRectangle({x:0,y:0,width:540,height:340,color:rgb(parseInt(color.slice(1,3),16)/255,parseInt(color.slice(3,5),16)/255,parseInt(color.slice(5,7),16)/255)});
 const line=(text:string,y:number,size=14)=>{let safe=text.replace(/[^\x20-\x7E\u00A0-\u00FF]/g,' ').slice(0,90);while(font.widthOfTextAtSize(safe,size)>320)safe=safe.slice(0,-1);page.drawText(safe,{x:24,y,size,font: y===285?bold:font,color:rgb(1,1,1)})};
 if(card.logo?.startsWith('data:image/png;base64,')&&card.logo.length<1000000){try{const logo=await doc.embedPng(Buffer.from(card.logo.slice(22),'base64'));const scale=Math.min(120/logo.width,40/logo.height);page.drawImage(logo,{x:365,y:280,width:logo.width*scale,height:logo.height*scale})}catch{}}
 line(card.ministry||'Carteirinha da igreja',315,10);line(card.category,285,23);line(card.name,238,18);line(card.unit,205,13);line('Válida até '+card.expires.split('-').reverse().join('/'),170);line('Emissão: cadastro oficial da igreja',50,10);line('Validação pela equipe autorizada.',32,10);
 const qr=await doc.embedPng(await QRCode.toBuffer(card.code!,{width:160,margin:2}));page.drawImage(qr,{x:365,y:105,width:150,height:150});
 return new Response(new Uint8Array(await doc.save()),{headers:{'Content-Type':'application/pdf','Content-Disposition':'attachment; filename="carteirinha.pdf"','Cache-Control':'private, no-store'}});
 }catch{return Response.json({error:'Não foi possível gerar a carteirinha.'},{status:503})}}
