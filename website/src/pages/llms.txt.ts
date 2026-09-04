import type { APIRoute } from 'astro';
import { absolute, markdownUrl, orderedPages } from '@/lib/llms';

/**
 * https://llmstxt.org — a short, linkable index of the documentation for LLMs.
 */
export const GET: APIRoute = ({ site }) => {
  const lines = [
    '# react-native-alarm-scheduler',
    '',
    '> Real, user-visible alarms for React Native and Expo apps. Schedules actual native alarms —',
    '> `AlarmManager.setAlarmClock` on Android with a foreground service that keeps ringing through',
    '> Doze and a killed app, and AlarmKit on iOS 26+ — rather than notifications that hope the',
    '> device is awake. Supports completion-gated alarms that only stop when the app says so.',
    '',
    'Android API 24+. iOS 15.1+ to install, iOS 26 SDK and runtime for AlarmKit scheduling.',
    'Requires a native build; not available in Expo Go. Web is unsupported beyond explicit no-ops.',
    '',
    '## Docs',
    '',
  ];

  for (const page of orderedPages()) {
    const url = absolute(site, markdownUrl(page.url));
    const description = page.data.description ? `: ${page.data.description}` : '';
    lines.push(`- [${page.data.title}](${url})${description}`);
  }

  lines.push(
    '',
    '## Optional',
    '',
    `- [Full documentation as one file](${absolute(site, '/llms-full.txt')})`,
    '- [Source repository](https://github.com/prashantrajm/react-native-alarm-scheduler)',
    '- [npm package](https://www.npmjs.com/package/react-native-alarm-scheduler)',
    '',
  );

  return new Response(lines.join('\n'), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
