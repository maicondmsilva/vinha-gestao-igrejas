import type { Metadata } from 'next';
import { Manrope } from 'next/font/google';
import './globals.css';
import './admin-vinha/admin-gate.css';
import ActionCoordinator from './ActionCoordinator';
import SupportChat from './SupportChat';
const manrope=Manrope({variable:'--font',subsets:['latin']});
export const metadata:Metadata={title:'Vinha — Gestão que frutifica',description:'Gestão completa para igrejas, pessoas e ministérios.'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="pt-BR"><body className={manrope.variable}>{children}<ActionCoordinator/><SupportChat/></body></html>}
