import lintofu from '@synapsestudios/lintofu';

export default [
  { ignores: ['**/.terraform/**'] },
  lintofu.configs.recommended,
];
