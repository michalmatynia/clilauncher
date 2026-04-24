#!/usr/bin/env node
// @ts-check

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

process.env.GEMINI_INITIAL_PROMPT = 'Ship beta now';
const { _test } = await import('../Sources/GeminiLauncherNative/Resources/gemini-automation-runner.mjs');

const cases = [
  {
    name: 'high_demand_panel',
    text: `We're currently experiencing high demand.

We apologize and appreciate your patience.

/model to switch models.












1. Keep trying

2. Switch to gemini-3-flash-preview

3. Stop`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'boxed_high_demand_panel',
    text: `We're currently experiencing high demand.

╭──────────────────────
│ 1) Keep trying
│ 2) Switch to gemini-3-flash-preview
│ 3) Stop
╰──────────────────────`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'bullet_style_panel',
    text: `The model is currently overloaded.

1) Keep trying
2) Switch to gemini-2.5-pro
3) Stop`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'unicode_bullet_panel',
    text: `We are currently experiencing high demand.

We apologize and appreciate your patience.

/model to switch models.

│ ● 1. Keep trying
│ ● 2. Switch to gemini-3-flash-preview
│ ● 3. Stop`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'unicode_bullet_parenthesized',
    text: `We're currently experiencing high demand.

╭──────────────────────
│ ● 1) Keep trying
│ ● 2) Switch to gemini-2.5-pro
│ ● 3) Stop
╰──────────────────────`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'simple_no_capacity',
    text: `No capacity available.

[1] Keep trying
[2] Switch to gemini-3-flash-preview
[3] Stop`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'compact_indexed',
    text: `We're currently experiencing high demand.

[1] Keep trying
[2] Switch to gemini-3-flash-preview
[3] Stop`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'mixed_format_no_empty_separator',
    text: `We are currently experiencing high demand.

╭───────────────────────────
│ ● 1) Keep trying
│ ● 2) Switch to gemini-2.0-flash
│ ● 3) Stop
╰───────────────────────────`,
    expectKind: 'capacity_menu',
    expectKeep: '1',
    expectSwitch: '2',
  },
  {
    name: 'non_capacity_plan_text',
    text: `Let's start from a clean plan.

1) Review the file
2) Run the tests
3) Commit changes`,
    expectKind: 'normal',
  },
  {
    name: 'non_capacity_question',
    text: `Which path should we take?

1) Option one
2) Option two
3) Option three`,
    expectKind: 'normal',
  },
  {
    name: 'permission_auto_save_panel',
    text: `Action required: Allow execution of: rm -rf dist

● 1. Allow once
● 2. Allow for this session
● 3. Allow this command for all future sessions ~/.gemini/policies/auto-sav…`,
    expectKind: 'permission',
    expectPermission: '3',
  },
  {
    name: 'permission_bracketed_command_panel',
    text: `╭──────────────────────────────────────────────────────────────────────────╮
│ ? Shell  Finding all test files in Kangur that mock useKangurAuth.      │
│ ╭──────────────────────────────────────────────────────────────────────╮ │
│ │ find src/features/kangur -name "*.test.tsx" -exec grep -l           │ │
│ │ "useKangurAuth:" {} +                                               │ │
│ ╰──────────────────────────────────────────────────────────────────────╯ │
│ Allow execution of [find]?                                             │
│                                                                        │
│ ● 1. Allow once                                                        │
│   2. Allow for this session                                            │
│   3. No, suggest changes (esc)                                         │
╰──────────────────────────────────────────────────────────────────────────╯`,
    expectKind: 'permission',
    expectPermission: '2',
  },
  {
    name: 'context_window_continue_warning',
    text: 'Sending this message (2253521 tokens) might exceed the remaining context window limit (986557 tokens).',
    expectKind: 'capacity_continue',
  },
];

let failures = 0;

for (const item of cases) {
  const snap = _test.detectSnapshotFromText(item.text, 'sim');
  if (snap.kind !== item.expectKind) {
    console.error(`[FAIL] ${item.name}: expected kind ${item.expectKind}, got ${snap.kind}`);
    failures += 1;
    continue;
  }

  if (item.expectKind !== 'capacity_menu') {
    if (snap.kind === item.expectKind) {
      if (item.expectKind === 'permission') {
        if (snap.targetOptionText !== item.expectPermission) {
          console.error(`[FAIL] ${item.name}: permission option expected ${item.expectPermission}, got ${String(snap.targetOptionText)}`);
          failures += 1;
        }
      }

      if (item.expectKind === 'capacity_continue') {
        if (snap.continueAction !== 'command') {
          console.error(`[FAIL] ${item.name}: continue action expected command, got ${String(snap.continueAction)}`);
          failures += 1;
        }
      }

      continue;
    }

    if (snap.kind === 'capacity_menu') {
      console.error(`[FAIL] ${item.name}: expected kind ${item.expectKind}, got capacity_menu`);
      failures += 1;
      continue;
    }

    console.error(`[FAIL] ${item.name}: expected kind ${item.expectKind}, got ${snap.kind}`);
    failures += 1;
    continue;
  }

  if (snap.keepOption?.numberText !== item.expectKeep) {
    console.error(`[FAIL] ${item.name}: keep option expected ${item.expectKeep}, got ${String(snap.keepOption?.numberText)}`);
    failures += 1;
  }
  if (snap.switchOption?.numberText !== item.expectSwitch) {
    console.error(`[FAIL] ${item.name}: switch option expected ${item.expectSwitch}, got ${String(snap.switchOption?.numberText)}`);
    failures += 1;
  }
}

const startupStatsSample = `╭──────────────────────────────────────────────────────────────────────────────╮
│  Session Stats                                                               │
│  Interaction Summary                                                         │
│  Session ID:                 d1431b19-95f2-43b5-871f-ddd618e64303            │
│  Auth Method:               Signed in with Google (info@sparksofsindri.com)  │
│  Tier:                       Gemini Code Assist for individuals              │
│  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
│  Performance                                                                 │
│  Wall Time:                  7.1s                                            │
│  Model Usage                                                                 │
│  Use /model to view model quota information                                  │
│  Model                         Reqs Input Tokens Cache Reads Output Tokens    │
│  gemini-2.5-flash                 1            0            0             0  │
│    ↳ main                         1            0            0             0  │
╰──────────────────────────────────────────────────────────────────────────────╯`;

const startupStatsSnapshot = _test.extractStartupStatsSnapshot(startupStatsSample);
if (!startupStatsSnapshot) {
  console.error('[FAIL] startup_stats_snapshot: expected snapshot to parse');
  failures += 1;
} else {
  if (startupStatsSnapshot.sessionID !== 'd1431b19-95f2-43b5-871f-ddd618e64303') {
    console.error(`[FAIL] startup_stats_snapshot: unexpected session ID ${String(startupStatsSnapshot.sessionID)}`);
    failures += 1;
  }
  if (!Array.isArray(startupStatsSnapshot.modelUsage) || startupStatsSnapshot.modelUsage.length !== 2) {
    console.error(`[FAIL] startup_stats_snapshot: expected 2 model usage rows, got ${String(startupStatsSnapshot.modelUsage?.length)}`);
    failures += 1;
  }
}

const startupStatsWithoutUsageSample = `╭──────────────────────────────────────────────────────────────────────────────╮
│  Session Stats                                                               │
│  Interaction Summary                                                         │
│  Session ID:                 2b7a5acf-fae6-49a7-b243-c3e424850832            │
│  Auth Method:                Signed in with Google (frommmishap@gmail.com)   │
│  Tier:                       Gemini Code Assist for individuals              │
│  Tool Calls:                 0 ( ✓ 0 x 0 )                                   │
│  Success Rate:               0.0%                                            │
│  Performance                                                                 │
│  Wall Time:                  39.4s                                           │
│  Agent Active:               0s                                              │
│    » API Time:               0s (0.0%)                                       │
│    » Tool Time:              0s (0.0%)                                       │
╰──────────────────────────────────────────────────────────────────────────────╯`;

const startupModelCapacitySample = `[gemini-preview-pty] Auto-sending startup /model (visible prompt field)...
╭──────────────────────────────────────────────────────────────────────────────╮
│ Select Model                                                                 │
│ ● 1. Manual (gemini-3-flash-preview)                                         │
│   2. Auto                                                                    │
│ Model usage                                                                  │
│ Pro             ▬▬▬▬▬▬▬▬▬▬▬▬▬▬                         82% Resets: 1:29 PM   │
│ Flash           ▬                                      7% Resets: 1:29 PM    │
│ Flash Lite                                             0%                    │
│ Press Esc to close                                                           │
╰──────────────────────────────────────────────────────────────────────────────╯`;

const startupClearEchoSample = `Type your message or @path/to/file
> /clear`;

const startupStatsWithoutUsage = _test.extractStartupStatsSnapshot(startupStatsWithoutUsageSample);
if (!startupStatsWithoutUsage) {
  console.error('[FAIL] startup_stats_snapshot_without_usage: expected snapshot to parse');
  failures += 1;
} else {
  if (startupStatsWithoutUsage.sessionID !== '2b7a5acf-fae6-49a7-b243-c3e424850832') {
    console.error(`[FAIL] startup_stats_snapshot_without_usage: unexpected session ID ${String(startupStatsWithoutUsage.sessionID)}`);
    failures += 1;
  }
  if (!Array.isArray(startupStatsWithoutUsage.modelUsage) || startupStatsWithoutUsage.modelUsage.length !== 0) {
    console.error(`[FAIL] startup_stats_snapshot_without_usage: expected 0 model usage rows, got ${String(startupStatsWithoutUsage.modelUsage?.length)}`);
    failures += 1;
  }
}

const startupModelCapacity = _test.extractStartupModelCapacitySnapshot(startupModelCapacitySample);
if (!startupModelCapacity) {
  console.error('[FAIL] startup_model_capacity_snapshot: expected snapshot to parse');
  failures += 1;
} else {
  if (startupModelCapacity.currentModel !== 'gemini-3-flash-preview') {
    console.error(`[FAIL] startup_model_capacity_snapshot: unexpected model ${String(startupModelCapacity.currentModel)}`);
    failures += 1;
  }
  if (!Array.isArray(startupModelCapacity.rows) || startupModelCapacity.rows.length !== 3) {
    console.error(`[FAIL] startup_model_capacity_snapshot: expected 3 rows, got ${String(startupModelCapacity.rows?.length)}`);
    failures += 1;
  }
  if (startupModelCapacity.rows?.[0]?.usedPercentage !== 82) {
    console.error(`[FAIL] startup_model_capacity_snapshot: expected first row 82%, got ${String(startupModelCapacity.rows?.[0]?.usedPercentage)}`);
    failures += 1;
  }
}

if (_test.canSendPromptCommandWithoutVisiblePrompt(
  { kind: 'startup-clear', createdAt: Date.now() - 1_500 },
  { kind: 'normal', chatPromptActive: false },
  { quietForMs: 1_500, waitedForMs: 1_500, authWaiting: false }
) !== true) {
  console.error('[FAIL] startup_clear_settled_normal_screen: expected startup clear command to allow settled normal screen send');
  failures += 1;
}

if (_test.hasLiveAuthWait('Type your message or @path/to/file\n> ', 'Waiting for authentication...') !== false) {
  console.error('[FAIL] live_auth_wait_ignores_stale_tail: expected stale auth text in history not to block startup commands');
  failures += 1;
}

if (_test.hasLiveAuthWait('Waiting for authentication... (Press Esc or Ctrl+C to cancel)', '') !== true) {
  console.error('[FAIL] live_auth_wait_detects_active_screen: expected live auth screen to block startup commands');
  failures += 1;
}

if (!startupClearEchoSample.includes('> /clear')) {
  console.error('[FAIL] startup_clear_echo_sample_missing: expected echoed clear sample to be present');
  failures += 1;
}

if (_test.hasStartupClearSettled(
  { kind: 'normal', chatPromptActive: false },
  {
    visibleText: 'Type your message or @path/to/file',
    quietForMs: 1_500,
    waitedForMs: 1_500,
  }
) !== true) {
  console.error('[FAIL] startup_clear_finalize_settled_screen: expected startup clear finalize to succeed after prompt returns');
  failures += 1;
}

if (_test.canSendPromptCommandWithoutVisiblePrompt(
  { kind: 'startup-stats', createdAt: Date.now() - 1_500 },
  { kind: 'normal', chatPromptActive: false },
  { quietForMs: 1_500, waitedForMs: 1_500, authWaiting: false }
) !== true) {
  console.error('[FAIL] startup_stats_settled_normal_screen: expected startup stats command to allow settled normal screen send');
  failures += 1;
}

if (_test.hasStartupStatsCaptureSettled(
  { kind: 'normal', chatPromptActive: false },
  {
    startupStatsObserved: true,
    visibleText: startupStatsWithoutUsageSample,
    quietForMs: 1_500,
    waitedForMs: 1_500,
  }
) !== false) {
  console.error('[FAIL] startup_stats_finalize_visible_panel: expected finalize to wait while session stats panel is still visible');
  failures += 1;
}

if (_test.hasStartupStatsCaptureSettled(
  { kind: 'normal', chatPromptActive: false },
  {
    startupStatsObserved: true,
    visibleText: 'Type your message or @path/to/file',
    quietForMs: 1_500,
    waitedForMs: 1_500,
  }
) !== true) {
  console.error('[FAIL] startup_stats_finalize_settled_screen: expected finalize to succeed after stats panel clears');
  failures += 1;
}

if (_test.hasStartupStatsCaptureSettled(
  { kind: 'normal', chatPromptActive: false },
  {
    startupStatsObserved: true,
    screenText: 'Type your message or @path/to/file',
    visibleText: `${startupStatsWithoutUsageSample}\nType your message or @path/to/file`,
    quietForMs: 1_500,
    waitedForMs: 1_500,
  }
) !== true) {
  console.error('[FAIL] startup_stats_finalize_ignores_historical_tail: expected finalize to use live screen over stale tail history');
  failures += 1;
}

const startupStatsCaptureSummary = _test.describeStartupStatsCapture({
  sessionID: '2b7a5acf-fae6-49a7-b243-c3e424850832',
  tier: 'Gemini Code Assist for individuals',
  authMethod: 'Signed in with Google (frommmishap@gmail.com)',
});
if (!startupStatsCaptureSummary.includes('session 2b7a5acf-fae6-49a7-b243-c3e424850832')
  || !startupStatsCaptureSummary.includes('tier Gemini Code Assist for individuals')) {
  console.error(`[FAIL] startup_stats_capture_summary: unexpected summary ${String(startupStatsCaptureSummary)}`);
  failures += 1;
}

const startupStatsFallback = _test.buildStartupStatsFallbackCommand({
  text: '/stats session',
  fallbackText: '/stats',
  fallbackUsed: false,
});
if (!startupStatsFallback || startupStatsFallback.text !== '/stats' || startupStatsFallback.fallbackUsed !== true) {
  console.error(`[FAIL] startup_stats_fallback_command: unexpected fallback ${JSON.stringify(startupStatsFallback)}`);
  failures += 1;
}

const unsupportedCapabilities = {
  startupStatsAutomationSupported: false,
  startupStatsAutomationDisabledReason: 'Gemini startup /stats automation is disabled for this smoke test.',
};

if (_test.shouldRequireStartupStatsBeforeInitialPrompt() !== true) {
  console.error('[FAIL] startup_stats_requirement_prompted: expected initial prompt to require startup stats');
  failures += 1;
}

if (_test.shouldLaunchInitialPromptWithLaunchArgs(unsupportedCapabilities) !== false) {
  console.error('[FAIL] startup_stats_launch_args_block: expected launch-args prompt injection to stay disabled');
  failures += 1;
}

const blockedReason = _test.resolveStartupStatsBlockReason({
  hasInitialPrompt: true,
  capabilities: unsupportedCapabilities,
  ptyAvailable: true,
});
if (!blockedReason.includes('startup /stats automation is disabled')) {
  console.error(`[FAIL] startup_stats_block_reason: unexpected reason ${String(blockedReason)}`);
  failures += 1;
}

const ptyUnavailableBlockedReason = _test.resolveStartupStatsBlockReason({
  hasInitialPrompt: true,
  capabilities: { startupStatsAutomationSupported: true },
  ptyAvailable: false,
});
if (!ptyUnavailableBlockedReason.includes('PTY backend unavailable')
  || !ptyUnavailableBlockedReason.includes('/clear')
  || !ptyUnavailableBlockedReason.includes('/stats')
  || !ptyUnavailableBlockedReason.includes('/model')) {
  console.error(`[FAIL] startup_stats_block_reason_pty_unavailable: unexpected reason ${String(ptyUnavailableBlockedReason)}`);
  failures += 1;
}

const originalCwd = process.cwd();
const originalPrompt = process.env.GEMINI_INITIAL_PROMPT;
const originalISOHome = process.env.GEMINI_ISO_HOME;
const smokeWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), 'clilauncher-smoke-workspace-'));
const smokeISOHome = fs.mkdtempSync(path.join(os.tmpdir(), 'clilauncher-smoke-iso-'));

try {
  const projectID = 'project-123';
  const geminiDir = path.join(smokeISOHome, '.gemini');
  const chatFile = path.join(geminiDir, 'tmp', projectID, 'chats', 'session-existing.json');
  fs.mkdirSync(path.dirname(chatFile), { recursive: true });
  fs.writeFileSync(chatFile, '{}\n');
  fs.mkdirSync(geminiDir, { recursive: true });
  fs.writeFileSync(
    path.join(geminiDir, 'projects.json'),
    `${JSON.stringify({ projects: { [smokeWorkspace]: projectID } }, null, 2)}\n`
  );
  fs.writeFileSync(path.join(smokeISOHome, '.iso-initialized'), '');

  process.env.GEMINI_INITIAL_PROMPT = 'Ship beta now';
  process.env.GEMINI_ISO_HOME = smokeISOHome;
  process.chdir(smokeWorkspace);

  const freshModuleURL = new URL(
    `../Sources/GeminiLauncherNative/Resources/gemini-automation-runner.mjs?fresh_session_smoke=${Date.now()}`,
    import.meta.url
  );
  const freshModule = await import(freshModuleURL.href);
  const freshReset = freshModule._test.prepareFreshWorkspaceSessionForPromptLaunch();
  const projects = JSON.parse(fs.readFileSync(path.join(geminiDir, 'projects.json'), 'utf8')).projects || {};

  if (freshReset.cleared !== true || freshReset.projectIdentifier !== projectID || freshReset.removedPathCount !== 1) {
    console.error(`[FAIL] fresh_session_reset: unexpected result ${JSON.stringify(freshReset)}`);
    failures += 1;
  }
  if (Object.prototype.hasOwnProperty.call(projects, smokeWorkspace)) {
    console.error('[FAIL] fresh_session_reset: workspace mapping was not removed from projects.json');
    failures += 1;
  }
  if (!fs.existsSync(chatFile)) {
    console.error('[FAIL] fresh_session_reset: expected existing chat history file to remain on disk');
    failures += 1;
  }

  const aliasWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), 'clilauncher-smoke-alias-workspace-'));
  const aliasISOHome = fs.mkdtempSync(path.join(os.tmpdir(), 'clilauncher-smoke-alias-iso-'));
  try {
    const aliasProjectID = 'project-alias';
    const aliasGeminiDir = path.join(aliasISOHome, '.gemini');
    const aliasChatFile = path.join(aliasGeminiDir, 'tmp', aliasProjectID, 'chats', 'session-existing.json');
    fs.mkdirSync(path.dirname(aliasChatFile), { recursive: true });
    fs.writeFileSync(aliasChatFile, '{}\n');
    fs.mkdirSync(aliasGeminiDir, { recursive: true });
    fs.writeFileSync(path.join(aliasISOHome, '.iso-initialized'), '');

    process.env.GEMINI_INITIAL_PROMPT = 'Ship beta now';
    process.env.GEMINI_ISO_HOME = aliasISOHome;
    process.chdir(aliasWorkspace);

    const aliasModuleURL = new URL(
      `../Sources/GeminiLauncherNative/Resources/gemini-automation-runner.mjs?fresh_session_alias_smoke=${Date.now()}`,
      import.meta.url
    );
    const aliasModule = await import(aliasModuleURL.href);
    const alternatePath = aliasModule._test.alternateWorkspacePathAlias(process.cwd()) || process.cwd();
    fs.writeFileSync(
      path.join(aliasGeminiDir, 'projects.json'),
      `${JSON.stringify({ projects: { [alternatePath]: aliasProjectID } }, null, 2)}\n`
    );

    const aliasReset = aliasModule._test.prepareFreshWorkspaceSessionForPromptLaunch();
    const aliasProjects = JSON.parse(fs.readFileSync(path.join(aliasGeminiDir, 'projects.json'), 'utf8')).projects || {};

    if (alternatePath === process.cwd()) {
      console.error('[FAIL] fresh_session_reset_alias: expected alternate workspace alias to differ from cwd');
      failures += 1;
    }
    if (aliasReset.cleared !== true || aliasReset.projectIdentifier !== aliasProjectID) {
      console.error(`[FAIL] fresh_session_reset_alias: unexpected result ${JSON.stringify(aliasReset)}`);
      failures += 1;
    }
    if (Object.prototype.hasOwnProperty.call(aliasProjects, alternatePath)) {
      console.error('[FAIL] fresh_session_reset_alias: alternate workspace mapping was not removed from projects.json');
      failures += 1;
    }
    if (!fs.existsSync(aliasChatFile)) {
      console.error('[FAIL] fresh_session_reset_alias: expected existing chat history file to remain on disk');
      failures += 1;
    }
  } finally {
    process.chdir(originalCwd);
    fs.rmSync(aliasWorkspace, { recursive: true, force: true });
    fs.rmSync(aliasISOHome, { recursive: true, force: true });
  }
} finally {
  process.chdir(originalCwd);
  if (originalPrompt == null) delete process.env.GEMINI_INITIAL_PROMPT;
  else process.env.GEMINI_INITIAL_PROMPT = originalPrompt;
  if (originalISOHome == null) delete process.env.GEMINI_ISO_HOME;
  else process.env.GEMINI_ISO_HOME = originalISOHome;
  fs.rmSync(smokeWorkspace, { recursive: true, force: true });
  fs.rmSync(smokeISOHome, { recursive: true, force: true });
}

if (failures > 0) {
  console.error(`automation detection smoke tests failed: ${failures}`);
  process.exit(1);
}

console.log('automation detection smoke tests passed');
