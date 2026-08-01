import { source } from './source';
import type { Root, Node } from 'fumadocs-core/page-tree';

export type DocPage = ReturnType<typeof source.getPages>[number];

/**
 * Pages in sidebar order (the order declared by each folder's meta.json), rather
 * than the arbitrary order the content collection happens to load them in.
 */
export function orderedPages(): DocPage[] {
  const pages: DocPage[] = [];
  const seen = new Set<string>();

  const visit = (nodes: Node[]) => {
    for (const node of nodes) {
      if (node.type === 'folder') {
        if (node.index) collect(node.index.url);
        visit(node.children);
      } else if (node.type === 'page') {
        collect(node.url);
      }
    }
  };

  const collect = (url: string) => {
    if (seen.has(url)) return;
    const page = source.getPages().find((p) => p.url === url);
    if (!page) return;
    seen.add(url);
    pages.push(page);
  };

  visit((source.getPageTree() as Root).children);

  // Anything not reachable from the tree still belongs in the output.
  for (const page of source.getPages()) collect(page.url);

  return pages;
}

const WRAPPERS = ['Callout', 'Cards', 'Steps', 'Step'];

/**
 * The document body as plain markdown: frontmatter, MDX imports and the JSX wrappers
 * the rendered site uses are all removed, so a model reads prose and code rather than
 * component syntax. Wrapper *contents* are kept — only the tags go.
 */
export function body(page: DocPage): string {
  return (page.data._raw.body ?? '')
    .replace(/^---\n[\s\S]*?\n---\n/, '')
    // <Card title="..." href="..." description="..." /> -> a markdown list item
    .replace(
      /^\s*<Card\s+title="([^"]*)"\s+href="([^"]*)"\s+description="([^"]*)"\s*\/>\s*$/gm,
      '- [$1]($2): $3',
    )
    .replace(/^import\s.*$/gm, '')
    .replace(
      new RegExp(`^\\s*</?(?:${WRAPPERS.join('|')})(?:\\s[^>]*)?/?>\\s*$`, 'gm'),
      '',
    )
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/** URL of a page's raw markdown. The index lives at /index.md, not /.md. */
export function markdownUrl(pageUrl: string): string {
  return pageUrl === '/' ? '/index.md' : `${pageUrl}.md`;
}

export function absolute(site: URL | undefined, path: string): string {
  return site ? new URL(path, site).href : path;
}
