import { createServer } from 'node:http';
import { createApp } from './http/app.ts';
import { DemoProvider } from './providers/demo.ts';
import { LiveProvider } from './providers/live.ts';
import { ScheduleService } from './service.ts';

const port = Number(process.env.PORT ?? 8787);
const source = process.env.SOURCE ?? 'live';

const provider = source === 'demo' ? new DemoProvider() : new LiveProvider();
const service = new ScheduleService(provider);
const server = createServer(createApp(service, (line) => console.log(line)));

server.listen(port, () => {
  console.log(`svitlo backend on http://localhost:${port} (source: ${provider.name})`);
});

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
