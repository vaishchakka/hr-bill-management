import { build } from 'esbuild';
await build({ entryPoints: ['frontend/connected.js'], bundle: true, format: 'esm', outfile: 'frontend/generated/connected.js', splitting: false, sourcemap: true });
