#!/usr/bin/env node
// @ts-check

import { _test } from '../Sources/GeminiLauncherNative/Resources/gemini-automation-runner.mjs';

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

if (failures > 0) {
  console.error(`automation detection smoke tests failed: ${failures}`);
  process.exit(1);
}

console.log('automation detection smoke tests passed');
