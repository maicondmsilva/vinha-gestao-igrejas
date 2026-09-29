import {NextResponse} from 'next/server';
import {platformSessionFrom} from '../../_auth';

export async function GET(request:Request){
  const session=await platformSessionFrom(request);
  if(!session)return NextResponse.json({authenticated:false,error:'Esta conta não pertence à administração interna da Vinha.'},{status:403});
  return NextResponse.json({authenticated:true,user:{name:session.name,email:session.email,role:session.role}});
}
