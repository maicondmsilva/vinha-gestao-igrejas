import { NextResponse } from 'next/server';
import { sessionFrom } from '../_auth';
export async function GET(request:Request){const session=await sessionFrom(request);if(!session)return NextResponse.json({authenticated:false},{status:401});return NextResponse.json({authenticated:true,user:session})}
