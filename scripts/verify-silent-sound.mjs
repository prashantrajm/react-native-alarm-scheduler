import fs from 'node:fs';
import path from 'node:path';

const soundPath = path.resolve('assets/alarm-scheduler-silence.caf');
const contents = fs.readFileSync(soundPath);

if (contents.length < 64 || contents.subarray(0, 4).toString('ascii') !== 'caff') {
  throw new Error('assets/alarm-scheduler-silence.caf is missing or invalid.');
}
