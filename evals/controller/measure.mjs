// node evals/controller/measure.mjs --plan SLUG --repo PATH | --session FILE [FILE ...]
// Prints the controller metrics of a plan's controller sessions in the
// repository at PATH, or of the transcripts named, as one JSON object. Reads
// only; calls no model.
import { flatten, measureSessions, planSessions } from './lib/sessions.mjs';

const args = process.argv.slice(2);
let files;
if (args.length === 4 && args[0] === '--plan' && args[2] === '--repo') files = planSessions(args[1], args[3]);
else if (args[0] === '--session' && args.length > 1) files = args.slice(1);
else {
  console.error('usage: measure.mjs --plan SLUG --repo PATH | --session FILE [FILE ...]');
  process.exit(2);
}
if (files.length === 0) {
  console.error(`measure: no controller session found for ${args[1]} in ${args[3]}`);
  process.exit(1);
}
console.log(JSON.stringify({ files, ...flatten(measureSessions(files)) }, null, 2));
