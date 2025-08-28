// Lightweight esbuild runner with on-the-fly Svelte support.
// Keeps RecurseEditor optional and only bundles when imported.

import { build } from 'esbuild'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { compile } from 'svelte/compiler'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// Minimal Svelte plugin for esbuild (no extra deps)
function sveltePlugin() {
  return {
    name: 'svelte-inline-compiler',
    setup(pluginBuild) {
      // Resolve .svelte files as-is so onLoad can read them
      pluginBuild.onResolve({ filter: /\.svelte$/ }, args => {
        const resolved = path.isAbsolute(args.path)
          ? args.path
          : path.join(args.resolveDir, args.path)
        return { path: resolved }
      })

      // Compile Svelte single-file components
      pluginBuild.onLoad({ filter: /\.svelte$/ }, async (args) => {
        const source = await fs.readFile(args.path, 'utf8')
        const filename = args.path

        const compiled = compile(source, {
          filename,
          css: true,
          dev: process.env.NODE_ENV !== 'production',
          generate: 'dom',
          format: 'esm'
        })

        // Inject CSS via a <style> tag to avoid separate CSS bundling
        let contents = compiled.js.code
        if (compiled.css && compiled.css.code) {
          const css = JSON.stringify(compiled.css.code)
          contents += `\n;(()=>{try{const s=document.createElement('style');s.dataset.svelte='${path.basename(filename)}';s.textContent=${css};document.head.appendChild(s)}catch(_) {}})();\n`
        }

        return {
          contents,
          loader: 'js',
          resolveDir: path.dirname(filename)
        }
      })
    }
  }
}

const args = process.argv.slice(2)
const watch = args.includes('--watch')

/** @type {import('esbuild').BuildOptions} */
const options = {
  entryPoints: [path.join(__dirname, 'js/app.js')],
  bundle: true,
  target: ['es2017'],
  outdir: path.join(__dirname, '..', 'priv', 'static', 'assets'),
  platform: 'browser',
  format: 'esm',
  splitting: true,
  sourcemap: process.env.NODE_ENV !== 'production',
  metafile: false,
  logLevel: 'info',
  plugins: [sveltePlugin()],
  define: {
    'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV || 'development')
  },
  entryNames: '[name]-[hash]',
  chunkNames: 'chunks/[name]-[hash]',
  assetNames: 'assets/[name]-[hash]',
  // Preserve Phoenix asset externals and mark optional libs as external so dynamic imports stay runtime-only
  external: [
    '/fonts/*',
    '/images/*',
    // Optional editors/libs loaded at runtime if present
    '@tiptap/*',
    'lowlight',
    'highlight.js/*',
    '@nocsi/recurse/*',
    'phoenix-colocated/*'
  ]
}

if (watch) {
  const ctx = await (await import('esbuild')).context(options)
  await ctx.watch()
  console.log('[build.mjs] watching for changes...')
} else {
  await build(options)
}
