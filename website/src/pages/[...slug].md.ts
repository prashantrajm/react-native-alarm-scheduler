import type { APIRoute } from 'astro';
import { absolute, body, orderedPages } from '@/lib/llms';

/**
 * Raw markdown for each page, at the page's own URL plus `.md`. Lets an agent fetch
 * exactly one topic instead of the whole site.
 */
export function getStaticPaths() {
  return orderedPages().map((page) => ({
    // The root page would otherwise be served at "/.md".
    params: { slug: page.slugs.length > 0 ? page.slugs.join('/') : 'index' },
    props: { url: page.url },
  }));
}

export const GET: APIRoute = ({ props, site }) => {
  const page = orderedPages().find((p) => p.url === props.url);
  if (!page) return new Response(undefined, { status: 404 });

  const parts = [`# ${page.data.title}`];
  if (page.data.description) parts.push('', page.data.description);
  parts.push('', `Source: ${absolute(site, page.url)}`, '', body(page), '');

  return new Response(parts.join('\n'), {
    headers: { 'Content-Type': 'text/markdown; charset=utf-8' },
  });
};
