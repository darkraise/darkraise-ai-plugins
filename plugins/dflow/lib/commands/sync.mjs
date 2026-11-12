export async function flush() {}
export async function pull() {}
export async function checkpoint() {}
export async function closeWorkstream() {}

export async function run(ctx, argv, { out }) {
  out('darkmem is off for this repository');
  return 0;
}
