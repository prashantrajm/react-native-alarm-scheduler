import type { APIRoute } from 'astro';
import { absolute, body, orderedPages } from '@/lib/llms';

/**
 * Every documentation page concatenated into one plain-text file, for pasting
 * into a model's context in a single step.
 */
export const GET: APIRoute = ({ site }) => {
  const pages = orderedPages();

  const parts = [
    '# react-native-alarm-scheduler',
    '',
    'Complete documentation, generated from https://react-native-alarm-scheduler.vercel.app',
    '',
    '---',
    '',
  ];

  for (const page of pages) {
    parts.push(`# ${page.data.title}`);
    if (page.data.description) parts.push('', page.data.description);
    parts.push('', `Source: ${absolute(site, page.url)}`, '', body(page), '', '---', '');
  }

  return new Response(parts.join('\n'), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
