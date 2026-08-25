'use client';
import { useState } from 'react';

const nav = ['⌂  Visão geral','♙  Pessoas','◈  Cultos e eventos','✓  Escalas','♫  Louvor','◌  Comunicação','↗  Transmissões','R$  Financeiro','▤  Relatórios'];
const events = [['30','AGO','Culto de Celebração','Domingo · 18:00','Escala 92%'],['03','SET','Encontro de Líderes','Quinta · 20:00','42 confirmados'],['06','SET','Conferência Viver','Domingo · 09:00','187 inscrições']];

export default function Home(){
  const [active,setActive]=useState(nav[0]);
  return <main className="shell">
    <aside className="side">
      <div className="brand"><i>V</i><div><b>Vinha</b><small>Gestão que frutifica</small></div></div>
      <p className="eyebrow">GESTÃO</p><nav>{nav.map(item=><button key={item} onClick={()=>setActive(item)} className={active===item?'active':''}>{item}</button>)}</nav>
      <div className="help"><i>?</i><div><b>Precisa de ajuda?</b><small>Fale com nosso time</small></div></div>
      <div className="user"><i>MA</i><div><b>Marina Alves</b><small>Administradora</small></div><span>⌄</span></div>
    </aside>
    <section className="main">
      <header><div className="tenant"><i>IC</i><div><small>Você está em</small><b>Igreja Central</b></div><span>⌄</span></div><div className="actions"><label>⌕ <input placeholder="Buscar pessoas, eventos..."/></label><button className="bell">♢<i>3</i></button><button className="create">＋ Criar novo</button></div></header>
      <div className="content">
        <div className="welcome"><div><p>SEGUNDA-FEIRA, 24 DE AGOSTO</p><h1>Olá, Marina. <span>Que bom ter você aqui.</span></h1><small>Acompanhe o que está acontecendo na sua comunidade hoje.</small></div><button>Este mês⌄</button></div>
        <section className="metrics">
          <Metric color="green" icon="♙" label="Membros ativos" value="1.284" trend="↗ 4,8% este mês"/>
          <Metric color="gold" icon="✦" label="Novos visitantes" value="48" trend="↗ 12,5% este mês"/>
          <Metric color="grape" icon="✓" label="Voluntários escalados" value="126" trend="18 aguardando resposta"/>
          <Metric color="coral" icon="R$" label="Contribuições" value="R$ 86,4 mil" trend="↗ 7,2% este mês"/>
        </section>
        <section className="grid">
          <article className="card chart-card"><Title over="ENVOLVIMENTO" title="Crescimento da comunidade" action="Últimos 6 meses⌄"/><div className="legend"><span>● Membros</span><span>● Visitantes</span></div><div className="chart"><div className="axis"><span>1.400</span><span>1.200</span><span>1.000</span><span>800</span><span>600</span></div><div className="plot"><div className="area"/><div className="line"/><div className="months"><span>MAR</span><span>ABR</span><span>MAI</span><span>JUN</span><span>JUL</span><span>AGO</span></div></div></div></article>
          <article className="card"><Title over="AGENDA" title="Próximos eventos" action="Ver todos"/><div className="event-list">{events.map(e=><div className="event" key={e[2]}><div className="date"><b>{e[0]}</b><small>{e[1]}</small></div><div><b>{e[2]}</b><small>{e[3]}</small></div><em>{e[4]}</em></div>)}</div><button className="wide">＋ Criar evento</button></article>
          <article className="card"><Title over="PRÓXIMO CULTO" title="Escala de domingo" action="EM MONTAGEM" badge/><div className="progress-copy"><span>23 de 25 posições confirmadas</span><b>92%</b></div><div className="progress"><i/></div><div className="team"><div><i>LF</i><i>RA</i><i>CS</i><i>＋9</i></div><small>Louvor, recepção, mídia e mais 5 ministérios</small></div><div className="warning"><i>!</i><div><b>2 posições precisam de atenção</b><small>Teclado e câmera 2 ainda estão vagas</small></div><button>Resolver</button></div></article>
          <article className="card live"><div className="cover"><b>● AO VIVO EM 6 DIAS</b><i>▶</i></div><div className="live-copy"><p>TRANSMISSÃO</p><h2>Culto de Celebração</h2><small>Agendado no YouTube · Dom, 18:00</small><div><button>Gerenciar transmissão</button><button>•••</button></div></div></article>
        </section>
      </div>
    </section>
  </main>
}

function Metric({color,icon,label,value,trend}:{color:string,icon:string,label:string,value:string,trend:string}){return <article className="metric"><i className={color}>{icon}</i><div><small>{label}</small><b>{value}</b><span>{trend}</span></div></article>}
function Title({over,title,action,badge=false}:{over:string,title:string,action:string,badge?:boolean}){return <div className="title"><div><p>{over}</p><h2>{title}</h2></div><button className={badge?'badge':''}>{action}</button></div>}
