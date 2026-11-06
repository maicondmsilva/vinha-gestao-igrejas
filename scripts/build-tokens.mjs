// Writes app/vinha-tokens.css from shared/design-tokens.ts (run after changing a token).
import {writeFileSync} from 'node:fs';
import {tokensCss} from '../shared/design-tokens.ts';
writeFileSync(new URL('../app/vinha-tokens.css', import.meta.url), tokensCss());
console.log('app/vinha-tokens.css atualizado');
