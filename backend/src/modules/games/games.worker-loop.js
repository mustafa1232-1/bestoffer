// A self-scheduling worker loop for game timers.
//
// Polling a fixed 150ms cadence costs several queries per second per instance
// even when nobody is playing. This loop instead sleeps until the next known
// deadline (bounded by maxDelayMs as a safety net for other instances' writes),
// and request handlers call wake() after committing player input so the next
// pass runs immediately. Phase changes therefore land within one query of their
// deadline, and an idle server issues about one cheap query per maxDelayMs.
export function createWorkerLoop(name, work, { minDelayMs = 25, maxDelayMs = 1000, busyDelayMs = 60 } = {}) {
  let stopped = true;
  let timer = null;
  let running = null;
  let wakeRequested = false;

  const schedule = (delay) => {
    if (stopped) return;
    clearTimeout(timer);
    timer = setTimeout(tick, Math.max(minDelayMs, Math.min(maxDelayMs, delay)));
    timer.unref?.();
  };

  async function tick() {
    timer = null;
    if (stopped || running) return;
    wakeRequested = false;
    let next = maxDelayMs;
    running = (async () => {
      try {
        const result = await work();
        if (result?.failed) console.warn(JSON.stringify({ event: `${name}_retry`, failed: result.failed }));
        if (result?.busy) next = busyDelayMs;
        else if (Number.isFinite(result?.nextDueMs)) next = result.nextDueMs;
      } catch (error) {
        console.warn(JSON.stringify({ event: `${name}_error`, code: error?.code || 'FAILED' }));
        next = 500;
      }
    })();
    await running;
    running = null;
    schedule(wakeRequested ? 0 : next);
  }

  return {
    start() {
      if (!stopped) return;
      stopped = false;
      schedule(0);
    },
    wake() {
      if (stopped) return;
      if (running) { wakeRequested = true; return; }
      schedule(0);
    },
    async stop() {
      stopped = true;
      clearTimeout(timer);
      timer = null;
      await running;
    },
  };
}
