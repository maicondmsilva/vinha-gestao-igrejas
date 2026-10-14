import type {AnchorHTMLAttributes} from 'react';
// Full document navigation also revalidates the operator gate and avoids
// retaining a previous route's client state in the Vinext production runtime.
export default function CentralLink(props:AnchorHTMLAttributes<HTMLAnchorElement>){return <a {...props}/>}
