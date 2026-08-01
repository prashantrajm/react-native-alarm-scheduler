// @ts-check
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import tailwindcss from '@tailwindcss/vite';
import mdx from '@astrojs/mdx';
import { unified } from '@astrojs/markdown-remark';
import {
  rehypeCode,
  remarkHeading,
  remarkStructure,
} from 'fumadocs-core/mdx-plugins';

// `remarkNpm` / `remarkCodeTab` expand into Fumadocs <Tabs>, which relies on React
// context. MDX content is server-rendered by Astro and passed into the <Docs> island
// as slot children, so that context never reaches it. Keep tab-producing plugins out.
const remarkPlugins = [
  remarkHeading,
  [remarkStructure, { exportAs: 'structuredData' }],
];
const rehypePlugins = [rehypeCode];

export default defineConfig({
  markdown: {
    processor: unified({
      syntaxHighlight: false,
      remarkPlugins,
      rehypePlugins,
    }),
  },
  integrations: [
    react(),
    mdx({
      extendMarkdownConfig: true,
      syntaxHighlight: false,
    }),
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
