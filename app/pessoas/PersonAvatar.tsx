'use client';
/** Círculo da pessoa: foto do cadastro (ou iniciais). Criança ganha anel colorido e selo "Kids". */
export default function PersonAvatar({photo, initials, name, child = false, size = 40}: {photo?: string; initials: string; name: string; child?: boolean; size?: number}) {
  return (
    <span className={'pa' + (child ? ' pa-kid' : '')} style={{width: size, height: size}} title={child ? 'Cadastro de criança' : undefined}>
      {photo ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={photo} alt={'Foto de ' + name} width={size} height={size} />
      ) : (
        <i aria-hidden="true">{initials}</i>
      )}
      {child && (
        <b className="pa-badge" aria-label="Criança">
          K
        </b>
      )}
    </span>
  );
}
