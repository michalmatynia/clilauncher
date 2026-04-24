#!/usr/bin/env node
// @ts-check

import process from 'node:process';
import { _test } from '../Sources/GeminiLauncherNative/Resources/gemini-automation-runner.mjs';

if (process.platform !== 'darwin') {
  console.log('python PTY smoke skipped: non-darwin platform');
  process.exit(0);
}

const pythonExecutable = _test.resolvePythonPtyExecutable(process.env.PATH || '');
if (!pythonExecutable) {
  console.log('python PTY smoke skipped: no python3 executable found');
  process.exit(0);
}

const backend = _test.createPythonPtyBackend(pythonExecutable);
const pty = backend.spawn(
  '/bin/sh',
  ['-c', 'printf "ready\\n"; read value; printf "x=%s\\n" "$value"'],
  { cwd: process.cwd(), env: process.env }
);

let output = '';
let sentInput = false;

await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => {
    try {
      pty.kill();
    } catch {
      // ignore
    }
    reject(new Error(`python PTY smoke timed out; collected output:\n${output}`));
  }, 4000);

  pty.onData((data) => {
    output += data;
    if (!sentInput && output.includes('ready')) {
      sentInput = true;
      pty.write('autonomy-smoke\r');
    }
  });

  pty.onExit(({ exitCode, signal }) => {
    clearTimeout(timeout);
    if (signal) {
      reject(new Error(`python PTY smoke exited by signal ${signal}; collected output:\n${output}`));
      return;
    }
    if (exitCode !== 0) {
      reject(new Error(`python PTY smoke failed with exit code ${exitCode}; collected output:\n${output}`));
      return;
    }
    if (!output.includes('ready')) {
      reject(new Error(`python PTY smoke never observed readiness output:\n${output}`));
      return;
    }
    if (!output.includes('x=autonomy-smoke')) {
      reject(new Error(`python PTY smoke did not round-trip input:\n${output}`));
      return;
    }
    resolve(null);
  });
});

console.log('python PTY smoke passed');
