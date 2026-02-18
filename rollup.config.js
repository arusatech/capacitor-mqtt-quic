import nodeResolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';

export default {
  input: 'dist/esm/index.js',
  output: [
    { file: 'dist/plugin.cjs.js', format: 'cjs', sourcemap: true, inlineDynamicImports: true },
    { file: 'dist/plugin.js', format: 'es', sourcemap: true, inlineDynamicImports: true },
  ],
  external: ['@capacitor/core'],
  plugins: [nodeResolve({ browser: true }), commonjs()],
};
