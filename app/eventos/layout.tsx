'use client';
import {useEffect,useState,type ReactNode} from 'react';
import {UnavailableFeature} from '../PilotAvailability';
import {canonicalEventPath} from '../../shared/event-info';
// Only the canonical event page and its authenticated team entrypoint are released.
export default function EventRouteBoundary({children}:{children:ReactNode}){
 const [allowed,setAllowed]=useState<boolean|null>(null);
 useEffect(()=>{setAllowed(canonicalEventPath(location.pathname))},[]);
 if(allowed===null)return <main><p role="status">Preparando o encontro…</p></main>;
 if(!allowed)return <UnavailableFeature/>;
 return <>{children}</>;
}
