// Kids · cuidados informados pelo responsável no app. O banco guarda um texto único (até 2.000 caracteres) que a equipe revisa;
// o app monta e lê esse texto em um formato padrão, item por item.
export type KidsCare = {food: string; allergy: string; special: string; noPhotos: boolean; notes: string};
const labels = {food: 'Restrição alimentar: ', allergy: 'Alergias: ', special: 'Necessidade especial: ', notes: 'Observações: '} as const;
const noPhotosLine = 'Fotos: não autorizadas';

export function parseCare(text: string): KidsCare {
  const care: KidsCare = {food: '', allergy: '', special: '', noPhotos: false, notes: ''};
  const free: string[] = [];
  for (const line of (text || '').split('\n')) {
    const key = (Object.keys(labels) as (keyof typeof labels)[]).find((k) => line.startsWith(labels[k]));
    if (key) care[key] = line.slice(labels[key].length).trim();
    else if (line.trim() === noPhotosLine) care.noPhotos = true;
    else if (line.trim()) free.push(line.trim());
  }
  if (free.length) care.notes = [care.notes, ...free].filter(Boolean).join(' ');
  return care;
}

export function composeCare(c: KidsCare): string {
  const one = (v: string) => v.replace(/\s+/g, ' ').trim();
  return [
    one(c.food) && labels.food + one(c.food),
    one(c.allergy) && labels.allergy + one(c.allergy),
    one(c.special) && labels.special + one(c.special),
    c.noPhotos && noPhotosLine,
    one(c.notes) && labels.notes + one(c.notes),
  ]
    .filter(Boolean)
    .join('\n')
    .slice(0, 2000);
}
