#!/usr/bin/env node
// @ts-check

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { spawn as spawnProcess } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const RUNNER_PATH = fileURLToPath(import.meta.url);
const RUNNER_BUILD_ID = '20260426T090000Z';
const RUNNER_LOG_FILE = (process.env.RUNNER_LOG_FILE || '').trim();
const MAX_LOG_SIZE = 5 * 1024 * 1024; // 5MB

if (RUNNER_LOG_FILE) {
  try {
    if (fs.existsSync(RUNNER_LOG_FILE) && fs.statSync(RUNNER_LOG_FILE).size > MAX_LOG_SIZE) {
      fs.renameSync(RUNNER_LOG_FILE, `${RUNNER_LOG_FILE}.old`);
    }
    const stamp = new Date().toISOString();
    const logStream = fs.createWriteStream(RUNNER_LOG_FILE, { flags: 'a' });
    logStream.write(`\n===== runner start ${stamp} pid=${process.pid} =====\n`);
    const origLog = console.log.bind(console);
    const origErr = console.error.bind(console);
    const wrap = (orig) => (...args) => {
      try { logStream.write(args.map(String).join(' ') + '\n'); } catch {}
      try {
        orig(...args);
      } catch (error) {
        if (isBenignStdoutWriteError(error)) return;
        throw error;
      }
    };
    console.log = wrap(origLog);
    console.error = wrap(origErr);
    process.on('exit', (code) => {
      try { logStream.write(`===== runner exit code=${code} =====\n`); logStream.end(); } catch {}
    });
    process.on('uncaughtException', (err) => {
      try { logStream.write(`uncaughtException: ${err?.stack || err}\n`); } catch {}
    });
    process.on('unhandledRejection', (err) => {
      try { logStream.write(`unhandledRejection: ${err?.stack || err}\n`); } catch {}
    });
  } catch (err) {
    console.error('[runner] Failed to open RUNNER_LOG_FILE:', err?.message || err);
  }
}

installStandardStreamErrorGuards();

const CLI_FLAVOR = resolveFlavor(process.env.CLI_FLAVOR || 'preview');
const FLAVOR_LABEL = defaultFlavorLabel(CLI_FLAVOR);
const DEFAULT_WRAPPER = defaultWrapperForFlavor(CLI_FLAVOR);
const DEFAULT_ISO_HOME = defaultISOHomeForFlavor(CLI_FLAVOR);
const MODEL_AUTO = isEnabled(process.env.GEMINI_MODEL_AUTO ?? process.env.MODEL_AUTO, false);
const GEMINI_AUTO_MODEL = String(process.env.GEMINI_AUTO_MODEL || 'auto').trim() || 'auto';

const MODELS = (
  process.env.MODEL_CHAIN ||
  defaultModelChainForFlavor(CLI_FLAVOR).join(',')
)
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);

if (MODELS.length === 0) {
  console.error('[fatal] MODEL_CHAIN resolved to an empty list.');
  process.exit(1);
}

const KEEP_TRY_MAX = toNumber(process.env.KEEP_TRY_MAX, 3);
const TRY_AGAIN_MIN_INTERVAL_MS = toNumber(process.env.TRY_AGAIN_MIN_INTERVAL_MS, 2500);
const MANUAL_OVERRIDE_MS = toNumber(process.env.MANUAL_OVERRIDE_MS, 20000);
const AUTOMATION_COOLDOWN_MS = toNumber(process.env.AUTOMATION_COOLDOWN_MS, 60000);
const FORCE_KILL_AFTER_MS = toNumber(process.env.FORCE_KILL_AFTER_MS, 1200);
const CAPACITY_RETRY_MS = toNumber(process.env.CAPACITY_RETRY_MS, 5000);
const MAX_CAPACITY_RETRY_MS = toNumber(process.env.MAX_CAPACITY_RETRY_MS, 30000);
const CAPACITY_EVENT_RESET_MS = toNumber(process.env.CAPACITY_EVENT_RESET_MS, 25000);
const CAPACITY_RECENT_MS = toNumber(process.env.CAPACITY_RECENT_MS, 15000);
const YOLO_REQUESTED = isEnabled(process.env.GEMINI_YOLO, false);
let yoloEnabledForSession = YOLO_REQUESTED;
const AUTO_CONTINUE_MAX_PER_EVENT = toNumber(process.env.AUTO_CONTINUE_MAX_PER_EVENT, YOLO_REQUESTED ? 1000 : 4);
const AUTO_RESTART_MAX_PER_WINDOW = toNumber(process.env.AUTO_RESTART_MAX_PER_WINDOW, YOLO_REQUESTED ? 50 : 3);
const AUTO_RESTART_WINDOW_MS = toNumber(process.env.AUTO_RESTART_WINDOW_MS, 120000);
const RAW_TAIL_MAX = toNumber(process.env.RAW_TAIL_MAX, 48000);
const NORMALIZED_TAIL_MAX = toNumber(process.env.NORMALIZED_TAIL_MAX, 16000);
const HOTKEY_TIMEOUT_MS = toNumber(process.env.HOTKEY_TIMEOUT_MS, 3000);
const STATIC_RECHECK_MS = toNumber(process.env.STATIC_RECHECK_MS, 1800);
const ACTION_RETRY_MIN_MS = toNumber(process.env.ACTION_RETRY_MIN_MS, 2600);
const PERMISSION_RETRY_MIN_MS = toNumber(process.env.PERMISSION_RETRY_MIN_MS, 1400);
const SCREEN_MAX_BUFFER_ROWS = toNumber(process.env.SCREEN_MAX_BUFFER_ROWS, 420);
const SCREEN_MAX_COLS = toNumber(process.env.SCREEN_MAX_COLS, 260);
const SCREEN_CAPTURE_LINES = toNumber(process.env.SCREEN_CAPTURE_LINES, 140);
const MENU_SELECT_MIN_MS = toNumber(process.env.MENU_SELECT_MIN_MS, 280);
const MENU_CONFIRM_MIN_MS = toNumber(process.env.MENU_CONFIRM_MIN_MS, 650);
const MENU_FALLBACK_AFTER_SELECTS = toNumber(process.env.MENU_FALLBACK_AFTER_SELECTS, 2);
const QUICK_RECHECK_MS = toNumber(process.env.QUICK_RECHECK_MS, 220);
const IGNORE_SIGHUP_GRACE_MS = toNumber(process.env.IGNORE_SIGHUP_GRACE_MS, 1500);
const DIALOG_BOTTOM_WINDOW_LINES = toNumber(process.env.DIALOG_BOTTOM_WINDOW_LINES, 100);
const DIALOG_CONTEXT_LINES = toNumber(process.env.DIALOG_CONTEXT_LINES, 6);
const CHAT_PROMPT_WINDOW_LINES = toNumber(process.env.CHAT_PROMPT_WINDOW_LINES, 8);
const INITIAL_PROMPT_RETRY_MS = toNumber(process.env.INITIAL_PROMPT_RETRY_MS, 450);
const INITIAL_PROMPT_SETTLE_MS = toNumber(process.env.INITIAL_PROMPT_SETTLE_MS, 900);
const INITIAL_PROMPT_MAX_WAIT_MS = toNumber(process.env.INITIAL_PROMPT_MAX_WAIT_MS, 8000);
const MENU_ACTION_LIMIT = toNumber(process.env.MENU_ACTION_LIMIT, 6);
const MENU_NAV_MAX_ATTEMPTS = toNumber(process.env.MENU_NAV_MAX_ATTEMPTS, 4);
const MENU_NUMERIC_MAX_ATTEMPTS = toNumber(process.env.MENU_NUMERIC_MAX_ATTEMPTS, 2);
const MENU_CONFIRM_MAX_ATTEMPTS = toNumber(process.env.MENU_CONFIRM_MAX_ATTEMPTS, 2);
const SESSION_COMPLETE_HOLD_OPEN_EXIT_CODE = 86;

const AUTO_CONTINUE_MODE = ((process.env.AUTO_CONTINUE_MODE || 'prompt_only').trim().toLowerCase());
const AUTO_CONTINUE_ON_CAPACITY = isEnabled(process.env.AUTO_CONTINUE_ON_CAPACITY, true);
const AUTO_ALLOW_SESSION_PERMISSIONS = isEnabled(process.env.AUTO_ALLOW_SESSION_PERMISSIONS, true);
const AUTO_DISABLE_ON_USAGE_LIMIT = isEnabled(process.env.AUTO_DISABLE_ON_USAGE_LIMIT, true);
const AUTOMATION_DEFAULT_ENABLED = isEnabled(process.env.AUTOMATION_ENABLED, true);
const NEVER_SWITCH = isEnabled(process.env.NEVER_SWITCH, false);
const DEBUG_AUTOMATION = isEnabled(process.env.DEBUG_AUTOMATION, false);
const DEBUG_LAUNCH = isEnabled(process.env.DEBUG_LAUNCH, false);
const QUIET_CHILD_NODE_WARNINGS = isEnabled(process.env.QUIET_CHILD_NODE_WARNINGS, true);
const SET_HOME_TO_ISO = isEnabled(process.env.PTY_SET_HOME_TO_ISO, false);
const RAW_OUTPUT = isEnabled(process.env.RAW_OUTPUT, false);
const RESUME_DEFAULT = isEnabled(process.env.RESUME_LATEST, true);
const GEMINI_INITIAL_PROMPT = (process.env.GEMINI_INITIAL_PROMPT || '').trim();
const STARTUP_CLEAR_COMMAND = (process.env.STARTUP_CLEAR_COMMAND || '/clear').trim();
const STARTUP_STATS_COMMAND = (process.env.STARTUP_STATS_COMMAND || '/stats').trim();
const STARTUP_MODEL_COMMAND = (process.env.STARTUP_MODEL_COMMAND || '/model').trim();
const STATS_SESSION_FALLBACK_COMMAND = (process.env.STATS_SESSION_FALLBACK_COMMAND || '/stats').trim();
const AUTH_COMMAND = (process.env.AUTH_COMMAND || '/auth').trim();
const MODEL_CHAIN_EXHAUSTED_ACTION = normalizeModelChainExhaustedAction(process.env.MODEL_CHAIN_EXHAUSTED_ACTION || 'auth');

const GEMINI_WRAPPER_ENV = process.env.GEMINI_WRAPPER || DEFAULT_WRAPPER;
const GEMINI_WRAPPER_ARGS = parseJsonArrayEnv(process.env.GEMINI_WRAPPER_ARGS_JSON);
const ISO_HOME =
  process.env.GEMINI_ISO_HOME ||
  process.env.GEMINI_PREVIEW_ISO_HOME ||
  process.env.GEMINI_NIGHTLY_ISO_HOME ||
  process.env.GEMINI_HOME ||
  DEFAULT_ISO_HOME;

const SHELL_EXECUTABLE = resolveExecutable(
  process.env.PTY_SHELL_EXECUTABLE || process.env.PTY_SHELL || '/bin/sh'
);
const WRAPPER_LAUNCH_MODE = ((process.env.WRAPPER_LAUNCH_MODE || 'auto').trim().toLowerCase());

const DEFAULT_HOTKEY_PREFIX = process.platform === 'darwin' ? 'ctrl-g' : 'ctrl-]';
const HOTKEY_PREFIX_NAME = (process.env.HOTKEY_PREFIX || DEFAULT_HOTKEY_PREFIX).trim().toLowerCase();
const { byte: HOTKEY_PREFIX_BYTE, label: HOTKEY_PREFIX_LABEL } = resolveHotkeyPrefix(HOTKEY_PREFIX_NAME);

const CONTINUE_COMMAND = (process.env.CONTINUE_COMMAND || 'continue').trim() || 'continue';
const CONTINUE_FALLBACK_COMMAND = (process.env.CONTINUE_FALLBACK_COMMAND || '').trim();
const STATS_SESSION_COMMAND = (process.env.STATS_SESSION_COMMAND || '/stats session').trim();
const MODEL_MANAGE_COMMAND = (process.env.MODEL_MANAGE_COMMAND || '/model manage').trim();
const MODEL_SWITCH_COMMAND_TEMPLATE = (process.env.MODEL_SWITCH_COMMAND_TEMPLATE || '/model set {model}').trim();
const MODEL_SWITCH_MODE = ((process.env.MODEL_SWITCH_MODE || 'manage').trim().toLowerCase());
const PERMISSION_OPTION_LABEL = (process.env.PERMISSION_OPTION_LABEL || 'allow this command for all future sessions').trim().toLowerCase();
const PERMISSION_OPTION_INDEX = Math.max(1, Math.min(9, toNumber(process.env.PERMISSION_OPTION_INDEX, 3)));
const PROMPT_COMMAND_SETTLE_MS = toNumber(process.env.PROMPT_COMMAND_SETTLE_MS, 900);
const STARTUP_VISIBLE_PROMPT_COMMAND_SETTLE_MS = toNumber(process.env.STARTUP_VISIBLE_PROMPT_COMMAND_SETTLE_MS, 180);
const PROMPT_SUBMIT_DELAY_MS = toNumber(process.env.PROMPT_SUBMIT_DELAY_MS, 80);
const PROMPT_SUBMIT_SETTLE_MS = toNumber(process.env.PROMPT_SUBMIT_SETTLE_MS, Math.max(PROMPT_COMMAND_SETTLE_MS, 250));
const PROMPT_SUBMIT_PROCESSING_GRACE_MS = toNumber(process.env.PROMPT_SUBMIT_PROCESSING_GRACE_MS, 750);
const STARTUP_FIRST_COMMAND_DELAY_MS = toNumber(process.env.STARTUP_FIRST_COMMAND_DELAY_MS, 180);
const MODEL_MANAGE_FLOW_TIMEOUT_MS = toNumber(process.env.MODEL_MANAGE_FLOW_TIMEOUT_MS, 8000);
const INITIAL_PROMPT_SUBMIT_CONFIRM_MS = toNumber(process.env.INITIAL_PROMPT_SUBMIT_CONFIRM_MS, 260);
const INITIAL_PROMPT_SUBMIT_RETRY_MAX = toNumber(process.env.INITIAL_PROMPT_SUBMIT_RETRY_MAX, 3);
const USAGE_LIMIT_ACTION_TTL_MS = Math.max(MODEL_MANAGE_FLOW_TIMEOUT_MS * 4, 15000);
const KEEP_LABELS = splitListEnv(process.env.KEEP_OPTION_LABELS, [
  'keep trying',
  'try again',
  'continue waiting',
  'retrying',
]);
const SWITCH_LABELS = splitListEnv(process.env.SWITCH_OPTION_LABELS, [
  'switch to',
  'switch model',
  'change model',
  'use gemini',
]);
const STOP_LABELS = splitListEnv(process.env.STOP_OPTION_LABELS, ['stop']);

let loadedPty = null;
let loadedPtyModuleName = null;
let activePty = null;
let activeChild = null;
let activeDisposables = [];
let shuttingDown = false;
let resumeEnabledThisRun = RESUME_DEFAULT;
let modelIndex = 0;
let activeRunId = 0;
let lastLaunchPlan = null;
let currentGeminiCliCapabilities = defaultGeminiCliCapabilities();

let rawTail = '';
let normalizedTail = '';
let sentInitialPrompt = false;
let lastUserPrompt = '';
let pendingPostUsageLimitAdvance = null;
let pendingPostCapacityAdvance = null;
let lastExistingUsageLimitHandlerAt = 0;
let lastModelSwitchSentAt = 0;
const SAFETY_NET_DEBOUNCE_MS = 5000;
let startupClearCompleted = false;
let startupStatsObserved = false;
let startupStatsSnapshot = null;
let startupStatsBlockedReason = '';
let startupStatsBlocksInitialPrompt = false;
let startupModelCapacityObserved = false;
let startupModelCapacitySnapshot = null;
let initialPromptSubmittedFingerprint = '';
let authHandoffInProgress = false;
let authRestartTelemetryPending = false;
let suppressInitialPromptForAuthRestart = false;
let stateGeneration = 0;
let currentSnapshot = makeSnapshot('normal');
let sawNoResumeSession = false;
let authWaitSince = 0;
let warnedAuthWait = false;
let warnedPolicyBanner = false;
let avoidProModelsForSession = false;
const AUTH_WAIT_WARN_MS = toNumber(process.env.AUTH_WAIT_WARN_MS, 15000);

let automationEnabled = AUTOMATION_DEFAULT_ENABLED;
let automationDisabledReason = automationEnabled ? '' : 'manual';
let automationPausedUntil = 0;
let promptAutoContinueAlways = false;

let hotkeyAwaitingCommand = false;
let hotkeyTimer = null;
let stdinBound = false;
let resizeBound = false;

let continueTimer = null;
let promptCommandTimer = null;
let scheduledPromptCommand = null;
let pendingPromptCommandNudgeTimer = null;
const pendingSubmitTimers = new Set();
let pendingSubmitSettleUntil = 0;
let initialPromptTimer = null;
let initialPromptSubmitConfirmTimer = null;
let pendingInitialPromptSubmit = null;
let restartTimer = null;
let forceKillTimer = null;
let automationResumeTimer = null;
let staticRecheckTimer = null;
let heartbeatTimer = null;
let initialPromptPendingSince = 0;
let lastTerminalDataAt = Date.now();

let demandHits = 0;
let lastDemandTs = 0;
let lastCapacityAt = 0;
let autoContinueAttempts = 0;
let autoRestartHistory = [];
let plannedAction = null;
let pendingPromptCommand = null;
let switching = false;
let lastChildExitAt = 0;
let menuPlan = null;
let screenModel = null;
let continueLoopArmed = Boolean(GEMINI_INITIAL_PROMPT);

const recentActionKeys = new Map();
const workspaceRequire = createRequire(path.join(process.cwd(), '__clilauncher_runner__.cjs'));

let lastHeartbeat = Date.now();
const HEARTBEAT_TIMEOUT_MS = 30000;

function checkHeartbeat() {
  if (activePty && Date.now() - lastHeartbeat > HEARTBEAT_TIMEOUT_MS) {
    console.error('[runner] Heartbeat timeout: child process appears frozen. Restarting...');
    cleanupAndExit(1);
  }
}

function startHeartbeatLoop() {
  clearHeartbeatLoop();
  heartbeatTimer = setInterval(checkHeartbeat, 5000);
}

function clearHeartbeatLoop() {
  if (!heartbeatTimer) return;
  clearInterval(heartbeatTimer);
  heartbeatTimer = null;
}

async function main() {
  lastHeartbeat = Date.now();
  validateConfig();
  fs.mkdirSync(ISO_HOME, { recursive: true });
  screenModel = new VirtualScreen(SCREEN_MAX_BUFFER_ROWS, SCREEN_MAX_COLS);
  startHeartbeatLoop();

  bindProcessCleanup();

  try {
    const { pty, moduleName } = await loadPtyModule();
    loadedPty = pty;
    loadedPtyModuleName = moduleName;

    bindUserInput();
    bindResizeHandling();
  } catch (error) {
    loadedPty = null;
    loadedPtyModuleName = 'direct-spawn-fallback';
    console.error(
      [
        `[${FLAVOR_LABEL}] PTY library unavailable; falling back to direct child process mode.`,
        `[${FLAVOR_LABEL}] Automation features and hotkeys are disabled in fallback mode.`,
        `[${FLAVOR_LABEL}] ${error instanceof Error ? error.message : String(error)}`,
      ].join('\n')
    );
  }

  spawnGemini();
}

async function loadPtyModule() {
  const errors = [];

  for (const moduleName of ['@lydell/node-pty', 'node-pty']) {
    try {
      const imported = await importResolvedPtyModule(moduleName);
      const candidate = imported?.spawn
        ? imported
        : imported?.default?.spawn
          ? imported.default
          : null;

      if (!candidate?.spawn) {
        throw new Error(`Module ${moduleName} loaded, but no spawn() export was found.`);
      }

      return { pty: candidate, moduleName };
    } catch (error) {
      errors.push(`${moduleName}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  const pythonExecutable = resolvePythonPtyExecutable(process.env.PATH || '');
  if (pythonExecutable) {
    return {
      pty: createPythonPtyBackend(pythonExecutable),
      moduleName: `python-pty-bridge (${pythonExecutable})`,
    };
  }

  throw new Error(
    [
      'Could not load a PTY library or locate a `python3` PTY fallback.',
      'Install one of these in the active workspace if you want interactive automation:',
      '  npm i @lydell/node-pty',
      '  npm i node-pty',
      '',
      'Or ensure `python3` is available on PATH so the bundled PTY bridge can be used.',
      '',
      errors.join('\n'),
    ].join('\n')
  );
}

async function importResolvedPtyModule(moduleName) {
  const workspaceResolved = resolveWorkspaceModule(moduleName);
  if (workspaceResolved) {
    return import(pathToFileURL(workspaceResolved).href);
  }
  return import(moduleName);
}

const PYTHON_PTY_BRIDGE_SOURCE = String.raw`
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios

args = sys.argv[1:]
if args and args[0] == '--':
    args = args[1:]

if not args:
    sys.stderr.write('python PTY bridge missing target command\n')
    sys.exit(2)

rows = max(1, int(os.environ.get('CODEX_PTY_ROWS', '30') or '30'))
cols = max(1, int(os.environ.get('CODEX_PTY_COLS', '120') or '120'))
master_fd, slave_fd = pty.openpty()

try:
    fcntl.ioctl(master_fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
except Exception:
    pass

child = subprocess.Popen(
    args,
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    cwd=os.getcwd(),
    env=os.environ.copy(),
    close_fds=True,
    start_new_session=True,
)
os.close(slave_fd)

stdin_fd = sys.stdin.fileno()
stdout_fd = sys.stdout.fileno()
stdin_open = True

def forward_signal(signum, _frame):
    if child.poll() is not None:
        return
    try:
        os.killpg(child.pid, signum)
    except ProcessLookupError:
        pass

for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(signum, forward_signal)

while True:
    read_fds = [master_fd]
    if stdin_open:
        read_fds.append(stdin_fd)

    ready, _, _ = select.select(read_fds, [], [], 0.05)

    if master_fd in ready:
        try:
            data = os.read(master_fd, 65536)
        except OSError:
            data = b''

        if data:
            os.write(stdout_fd, data)
        elif child.poll() is not None:
            break

    if stdin_open and stdin_fd in ready:
        try:
            data = os.read(stdin_fd, 4096)
        except OSError:
            data = b''

        if data:
            os.write(master_fd, data)
        else:
            stdin_open = False

    if child.poll() is not None and master_fd not in ready:
        break

exit_code = 1

try:
    exit_code = child.wait(timeout=0.5)
except subprocess.TimeoutExpired:
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        exit_code = child.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            exit_code = child.wait(timeout=0.5)
        except Exception:
            exit_code = 1

try:
    os.close(master_fd)
except OSError:
    pass

sys.exit(exit_code)
`;

function resolvePythonPtyExecutable(pathEnv) {
  const candidates = [];
  const resolved = resolveExecutableDetailed('python3', pathEnv).resolvedPath;
  if (resolved) candidates.push(resolved);

  for (const candidate of ['/usr/bin/python3', '/opt/homebrew/bin/python3', '/usr/local/bin/python3']) {
    if (!candidate || candidates.includes(candidate)) continue;
    candidates.push(candidate);
  }

  for (const candidate of candidates) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      return candidate;
    } catch {
      // ignore
    }
  }

  return '';
}

function createPythonPtyBackend(pythonExecutable) {
  return {
    spawn(file, args = [], options = {}) {
      const env = {};
      for (const [key, value] of Object.entries(options.env || process.env)) {
        if (typeof value === 'string') env[key] = value;
      }
      env.CODEX_PTY_ROWS = String(Math.max(1, Number(options.rows) || getTerminalRows()));
      env.CODEX_PTY_COLS = String(Math.max(1, Number(options.cols) || getTerminalColumns()));

      const child = spawnProcess(
        pythonExecutable,
        ['-c', PYTHON_PTY_BRIDGE_SOURCE, '--', file, ...args],
        {
          cwd: options.cwd || process.cwd(),
          env,
          stdio: ['pipe', 'pipe', 'pipe'],
        }
      );

      const dataListeners = new Set();
      const exitListeners = new Set();
      let finished = false;

      const emitData = (chunk) => {
        const text = typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
        if (!text) return;
        for (const listener of [...dataListeners]) {
          try {
            listener(text);
          } catch {
            // ignore listener failures
          }
        }
      };

      const emitExit = (exitCode, signal) => {
        if (finished) return;
        finished = true;
        for (const listener of [...exitListeners]) {
          try {
            listener({ exitCode, signal });
          } catch {
            // ignore listener failures
          }
        }
      };

      child.stdout?.on('data', emitData);
      child.stderr?.on('data', emitData);
      child.on('exit', (exitCode, signal) => {
        emitExit(typeof exitCode === 'number' ? exitCode : 0, signal);
      });
      child.on('error', (error) => {
        emitData(`[${FLAVOR_LABEL}] Python PTY bridge error: ${error instanceof Error ? error.message : String(error)}\n`);
        emitExit(1, null);
      });

      return {
        write(text) {
          if (child.stdin?.destroyed) return;
          child.stdin?.write(text);
        },
        resize() {
          // The Python bridge applies the initial terminal size only.
        },
        kill(signal = 'SIGTERM') {
          child.kill(signal);
        },
        end() {
          child.stdin?.end();
        },
        onData(callback) {
          dataListeners.add(callback);
          return {
            dispose() {
              dataListeners.delete(callback);
            },
          };
        },
        onExit(callback) {
          exitListeners.add(callback);
          return {
            dispose() {
              exitListeners.delete(callback);
            },
          };
        },
      };
    },
  };
}

function resolveWorkspaceModule(moduleName) {
  try {
    return workspaceRequire.resolve(moduleName);
  } catch {
    return null;
  }
}

function spawnGemini() {
  if (loadedPty) {
    spawnGeminiWithPty();
    return;
  }
  spawnGeminiDirect();
}

function spawnGeminiWithPty() {
  clearAllTimers();
  disposeActiveListeners();
  activePty = null;
  activeChild = null;
  plannedAction = null;
  pendingPromptCommand = null;
  switching = false;

  activeRunId += 1;
  if (activeRunId === 1) {
    console.log(
      `[${FLAVOR_LABEL}] Automation: ${automationEnabled ? 'ENABLED' : 'DISABLED'} (Hotkey: ${HOTKEY_PREFIX_LABEL} a to toggle, ${HOTKEY_PREFIX_LABEL} o on, ${HOTKEY_PREFIX_LABEL} x off)`
    );
  }
  screenModel?.reset();
  clearMenuPlan();
  rawTail = '';
  normalizedTail = '';
  demandHits = 0;
  lastDemandTs = 0;
  lastCapacityAt = 0;
  autoContinueAttempts = 0;
  sawNoResumeSession = false;
  sentInitialPrompt = false;
  startupClearCompleted = false;
  authWaitSince = 0;
  warnedAuthWait = false;
  warnedPolicyBanner = false;
  stateGeneration = 0;
  currentSnapshot = makeSnapshot('normal');
  startupStatsObserved = false;
  startupStatsSnapshot = null;
  startupStatsBlockedReason = '';
  startupStatsBlocksInitialPrompt = false;
  startupModelCapacityObserved = false;
  startupModelCapacitySnapshot = null;
  initialPromptSubmittedFingerprint = '';
  pendingInitialPromptSubmit = null;
  initialPromptPendingSince = 0;
  lastTerminalDataAt = Date.now();
  lastChildExitAt = 0;
  recentActionKeys.clear();
  continueLoopArmed = Boolean(GEMINI_INITIAL_PROMPT);
  pendingPostUsageLimitAdvance = null;
  pendingPostCapacityAdvance = null;
  lastExistingUsageLimitHandlerAt = 0;
  lastSafetyNetAdvanceAt = 0;
  lastSafetyNetAdvanceFromModel = '';
  lastDetectedApiUsageLimitFingerprint = '';

  if (automationDisabledReason === 'usage_limit') {
    automationEnabled = AUTOMATION_DEFAULT_ENABLED;
    automationDisabledReason = automationEnabled ? '' : 'manual';
  }

  const model = currentModel();
  const wrapperInfo = inspectCommandTarget(GEMINI_WRAPPER_ENV, process.env.PATH || '');
  currentGeminiCliCapabilities = resolveGeminiCliCapabilities(wrapperInfo);
  const postAuthTelemetryLaunch = authRestartTelemetryPending;
  const suppressInitialPrompt = suppressInitialPromptForAuthRestart || postAuthTelemetryLaunch;
  const freshSessionReset = suppressInitialPrompt
    ? makeFreshSessionPrepSkippedResult('account change telemetry restart')
    : prepareFreshWorkspaceSessionForPromptLaunch();
  const env = buildChildEnv(currentGeminiCliCapabilities);
  const compatibilitySystemSettingsPath = resolveActiveCompatibilitySystemSettingsPath(env, currentGeminiCliCapabilities);
  const { args, canResume, hasInitialPrompt, launchesWithInitialPrompt } = buildGeminiArgs(model, {
    allowLaunchPrompt: !suppressInitialPrompt && shouldLaunchInitialPromptWithLaunchArgs(currentGeminiCliCapabilities, { ptyAvailable: true }),
    suppressInitialPrompt,
  });
  const launchBlockedStartupStatsReason = launchesWithInitialPrompt
    ? ''
    : resolveStartupStatsBlockReason({
      hasInitialPrompt,
      capabilities: currentGeminiCliCapabilities,
      ptyAvailable: true,
    });
  sentInitialPrompt = launchesWithInitialPrompt || suppressInitialPrompt;
  continueLoopArmed = Boolean(GEMINI_INITIAL_PROMPT) && !suppressInitialPrompt;
  const launchArgs = [...GEMINI_WRAPPER_ARGS, ...args];
  pendingPromptCommand = postAuthTelemetryLaunch
    ? buildPostAuthTelemetryCommand()
    : (launchBlockedStartupStatsReason
      ? null
      : (launchesWithInitialPrompt ? null : buildStartupCommandPipeline(currentGeminiCliCapabilities)));
  const launchPlan = buildLaunchPlan(wrapperInfo, launchArgs);
  lastLaunchPlan = launchPlan;
  if (launchBlockedStartupStatsReason) {
    setStartupStatsBlocked(launchBlockedStartupStatsReason, {
      emitBanner: false,
      blocksInitialPrompt: false,
    });
  }

  logLaunchBanner({
    model,
    canResume,
    wrapperInfo,
    launchPlan,
    hasInitialPrompt,
    launchesWithInitialPrompt,
    geminiCliCapabilities: currentGeminiCliCapabilities,
    compatibilitySystemSettingsPath,
    startupPipelineQueued: Boolean(pendingPromptCommand),
    startupStatsBlockedReason: launchBlockedStartupStatsReason,
    startupStatsBlocksInitialPrompt,
    freshSessionReset,
  });
  if (postAuthTelemetryLaunch && pendingPromptCommand) {
    console.error(`\n[${FLAVOR_LABEL}] Account change telemetry: running ${STARTUP_STATS_COMMAND} -> ${STARTUP_MODEL_COMMAND} without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
  }

  let ptyProcess;
  try {
    ptyProcess = loadedPty.spawn(launchPlan.file, launchPlan.args, buildPtyOptions(env));
  } catch (error) {
    const fallback = maybeBuildFallbackLaunchPlan(error, wrapperInfo, launchArgs, launchPlan);
    if (!fallback) {
      if (fallbackToDirectSpawnForPtyError(error)) return;
      throw wrapSpawnError(error, wrapperInfo, launchPlan);
    }
    lastLaunchPlan = fallback;
    console.error(`[${FLAVOR_LABEL}] Direct spawn failed, retrying via clean shell exec: ${error instanceof Error ? error.message : String(error)}`);
    try {
      ptyProcess = loadedPty.spawn(fallback.file, fallback.args, buildPtyOptions(env));
    } catch (fallbackError) {
      if (fallbackToDirectSpawnForPtyError(fallbackError)) return;
      throw wrapSpawnError(fallbackError, wrapperInfo, fallback);
    }
  }

  activePty = ptyProcess;
  const runId = activeRunId;

  activeDisposables.push(
    ptyProcess.onData((data) => {
      if (runId !== activeRunId || shuttingDown) return;
      handleTerminalData(runId, data);
      writeStdoutSafely(data);
    })
  );

  activeDisposables.push(
    ptyProcess.onExit(({ exitCode, signal }) => {
      if (runId !== activeRunId || shuttingDown) return;
      activePty = null;
      clearAllTimers();
      disposeActiveListeners();
      handleChildExit({ runId, exitCode, signal });
    })
  );
}

function spawnGeminiDirect() {
  clearAllTimers();
  disposeActiveListeners();
  activePty = null;
  activeChild = null;
  plannedAction = null;
  pendingPromptCommand = null;
  switching = false;
  lastChildExitAt = 0;

  activeRunId += 1;
  const runId = activeRunId;
  continueLoopArmed = Boolean(GEMINI_INITIAL_PROMPT);
  startupClearCompleted = false;
  startupStatsObserved = false;
  startupStatsSnapshot = null;
  startupStatsBlockedReason = '';
  startupStatsBlocksInitialPrompt = false;
  startupModelCapacityObserved = false;
  startupModelCapacitySnapshot = null;
  initialPromptSubmittedFingerprint = '';
  pendingInitialPromptSubmit = null;
  const model = currentModel();
  const wrapperInfo = inspectCommandTarget(GEMINI_WRAPPER_ENV, process.env.PATH || '');
  currentGeminiCliCapabilities = resolveGeminiCliCapabilities(wrapperInfo);
  const postAuthTelemetryLaunch = authRestartTelemetryPending;
  const suppressInitialPrompt = suppressInitialPromptForAuthRestart || postAuthTelemetryLaunch;
  const freshSessionReset = suppressInitialPrompt
    ? makeFreshSessionPrepSkippedResult('account change telemetry restart')
    : prepareFreshWorkspaceSessionForPromptLaunch();
  const { args, canResume, hasInitialPrompt, launchesWithInitialPrompt } = buildGeminiArgs(model, {
    allowLaunchPrompt: !suppressInitialPrompt && shouldLaunchInitialPromptWithLaunchArgs(currentGeminiCliCapabilities, { ptyAvailable: false }),
    suppressInitialPrompt,
  });
  const launchBlockedStartupStatsReason = launchesWithInitialPrompt
    ? ''
    : resolveStartupStatsBlockReason({
      hasInitialPrompt,
      capabilities: currentGeminiCliCapabilities,
      ptyAvailable: false,
    });
  sentInitialPrompt = launchesWithInitialPrompt || suppressInitialPrompt;
  continueLoopArmed = Boolean(GEMINI_INITIAL_PROMPT) && !suppressInitialPrompt;
  const env = buildChildEnv(currentGeminiCliCapabilities);
  const launchArgs = [...GEMINI_WRAPPER_ARGS, ...args];
  const compatibilitySystemSettingsPath = resolveActiveCompatibilitySystemSettingsPath(env, currentGeminiCliCapabilities);
  const launchPlan = buildLaunchPlan(wrapperInfo, launchArgs);
  lastLaunchPlan = launchPlan;
  if (launchBlockedStartupStatsReason) {
    setStartupStatsBlocked(launchBlockedStartupStatsReason, { emitBanner: false });
  }

  logLaunchBanner({
    model,
    canResume,
    wrapperInfo,
    launchPlan,
    hasInitialPrompt,
    launchesWithInitialPrompt,
    geminiCliCapabilities: currentGeminiCliCapabilities,
    compatibilitySystemSettingsPath,
    startupPipelineQueued: false,
    startupStatsBlockedReason: launchBlockedStartupStatsReason,
    startupStatsBlocksInitialPrompt,
    freshSessionReset,
  });
  if (postAuthTelemetryLaunch && pendingPromptCommand) {
    console.error(`\n[${FLAVOR_LABEL}] Account change telemetry: running ${STARTUP_STATS_COMMAND} -> ${STARTUP_MODEL_COMMAND} without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
  }

  const child = spawnProcess(launchPlan.file, launchPlan.args, {
    cwd: process.cwd(),
    env,
    stdio: 'inherit',
  });

  activeChild = child;
  child.on('exit', (exitCode, signal) => {
    if (runId !== activeRunId || shuttingDown) return;
    activeChild = null;
    handleChildExit({
      runId,
      exitCode: typeof exitCode === 'number' ? exitCode : 0,
      signal,
    });
  });
  child.on('error', (error) => {
    if (runId !== activeRunId || shuttingDown) return;
    failWithCleanup(wrapSpawnError(error, wrapperInfo, launchPlan));
  });
}

function buildPtyOptions(env) {
  return {
    name: process.env.TERM || 'xterm-256color',
    cols: getTerminalColumns(),
    rows: getTerminalRows(),
    cwd: process.cwd(),
    env,
  };
}

function fallbackToDirectSpawnForPtyError(error) {
  if (!shouldFallbackToDirectSpawnForPtyError(error)) return false;

  loadedPty = null;
  loadedPtyModuleName = 'runtime-direct-spawn-fallback';
  unbindUserInput();
  unbindResizeHandling();

  console.error(
    [
      `[${FLAVOR_LABEL}] PTY backend failed during spawn; falling back to direct child process mode.`,
      `[${FLAVOR_LABEL}] Automation features and hotkeys are disabled for this run.`,
      `[${FLAVOR_LABEL}] ${error instanceof Error ? error.message : String(error)}`,
    ].join('\n')
  );

  spawnGeminiDirect();
  return true;
}

function shouldFallbackToDirectSpawnForPtyError(error) {
  const text = error instanceof Error
    ? `${error.message}\n${error.stack || ''}`
    : String(error);

  return /posix_openpt failed|forkpty\(3\) failed|openpty failed|device not configured|cannot allocate pty/i.test(text);
}

function writeStdoutSafely(data) {
  if (process.stdout.destroyed || process.stdout.writableEnded) return;
  try {
    process.stdout.write(data);
  } catch (error) {
    if (isBenignStdoutWriteError(error)) return;
    throw error;
  }
}

function installStandardStreamErrorGuards() {
  const guard = (error) => {
    if (isBenignStdoutWriteError(error)) return;
    try {
      fs.writeSync(2, `[runner] terminal stream error: ${error instanceof Error ? error.stack || error.message : String(error)}\n`);
    } catch {
      // Nothing useful to do if stderr is also unavailable.
    }
  };

  try { process.stdout.on('error', guard); } catch {}
  try { process.stderr.on('error', guard); } catch {}
}

function isBenignStdoutWriteError(error) {
  const text = error instanceof Error
    ? `${error.message}\n${error.stack || ''}`
    : String(error);

  return /\bEIO\b|\bEPIPE\b|ERR_STREAM_DESTROYED/i.test(text);
}

function buildGeminiArgs(model, options = {}) {
  const hasInitialPrompt = Boolean(GEMINI_INITIAL_PROMPT) && !Boolean(options.suppressInitialPrompt);
  const shouldForceFreshSession = hasInitialPrompt;
  const canResume = !shouldForceFreshSession && resumeEnabledThisRun && workspaceHasResumableSessions();
  const args = [];
  if (MODEL_AUTO) {
    args.push('--model', GEMINI_AUTO_MODEL);
  } else if (model) {
    args.push('--model', model);
  }
  const launchesWithInitialPrompt = Boolean(options.allowLaunchPrompt) && hasInitialPrompt;

  if (canResume) {
    args.push('--resume', 'latest');
  }

  if (launchesWithInitialPrompt) {
    args.push('--prompt-interactive', GEMINI_INITIAL_PROMPT);
  }

  if (yoloEnabledForSession) {
    args.push('--yolo');
  }

  if (RAW_OUTPUT) {
    args.push('--raw-output', '--accept-raw-output-risk');
  }

  return { args, canResume, hasInitialPrompt, launchesWithInitialPrompt };
}

function buildChildEnv(geminiCliCapabilities = currentGeminiCliCapabilities) {
  const env = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (typeof value === 'string') env[key] = value;
  }

  env.CLI_FLAVOR = CLI_FLAVOR;
  env.GEMINI_MODEL_AUTO = MODEL_AUTO ? '1' : '0';
  env.GEMINI_AUTO_MODEL = GEMINI_AUTO_MODEL;
  env.GEMINI_ISO_HOME = ISO_HOME;
  if (CLI_FLAVOR === 'preview') env.GEMINI_PREVIEW_ISO_HOME = ISO_HOME;
  if (CLI_FLAVOR === 'nightly') env.GEMINI_NIGHTLY_ISO_HOME = ISO_HOME;
  if (CLI_FLAVOR === 'stable') env.GEMINI_HOME = ISO_HOME;
  env.GEMINI_YOLO = yoloEnabledForSession ? '1' : '0';
  if (SET_HOME_TO_ISO) env.HOME = ISO_HOME;
  if (QUIET_CHILD_NODE_WARNINGS && !env.NODE_NO_WARNINGS) {
    env.NODE_NO_WARNINGS = '1';
  }
  const compatibilitySystemSettings = ensureGeminiCliCompatibilitySystemSettings(geminiCliCapabilities, {
    isoHome: ISO_HOME,
    inheritedSystemSettingsPath: env.GEMINI_CLI_SYSTEM_SETTINGS_PATH,
  });
  if (compatibilitySystemSettings.path) {
    env.GEMINI_CLI_SYSTEM_SETTINGS_PATH = compatibilitySystemSettings.path;
  }

  return env;
}

function ensureGeminiCliCompatibilitySystemSettings(geminiCliCapabilities = currentGeminiCliCapabilities, options = {}) {
  const overrideSettings = geminiCliCapabilities?.systemSettingsOverride;
  if (!isPlainObject(overrideSettings)) {
    return { path: '', created: false };
  }

  const inheritedSystemSettingsPath = String(options.inheritedSystemSettingsPath || '').trim();
  if (inheritedSystemSettingsPath) {
    return { path: inheritedSystemSettingsPath, created: false };
  }

  const isoHome = String(options.isoHome || ISO_HOME || '').trim();
  if (!isoHome) {
    return { path: '', created: false };
  }

  try {
    const overrideDir = path.join(isoHome, '.clilauncher');
    const versionToken = normalizeVersionString(geminiCliCapabilities?.version) || 'compatibility';
    const overridePath = path.join(overrideDir, `gemini-cli-system-settings-${versionToken}.json`);
    fs.mkdirSync(overrideDir, { recursive: true });
    fs.writeFileSync(overridePath, JSON.stringify(overrideSettings, null, 2) + '\n', 'utf8');
    return { path: overridePath, created: true };
  } catch {
    return { path: '', created: false };
  }
}

function resolveActiveCompatibilitySystemSettingsPath(env, geminiCliCapabilities = currentGeminiCliCapabilities) {
  if (!geminiCliCapabilities?.systemSettingsOverrideReason) return '';

  const pathFromEnv = String(env?.GEMINI_CLI_SYSTEM_SETTINGS_PATH || '').trim();
  if (!pathFromEnv) return '';

  const inheritedPath = String(process.env.GEMINI_CLI_SYSTEM_SETTINGS_PATH || '').trim();
  return pathFromEnv !== inheritedPath ? pathFromEnv : '';
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function isoHomeLooksInitialized() {
  try {
    const sentinel = path.join(ISO_HOME, '.iso-initialized');
    if (fs.existsSync(sentinel)) return true;
    if (!fs.existsSync(ISO_HOME)) return false;
    const entries = fs.readdirSync(ISO_HOME);
    return entries.some((entry) => entry && entry !== 'Library' && entry !== '.DS_Store');
  } catch {
    return false;
  }
}

function workspaceHasResumableSessions() {
  if (!isoHomeLooksInitialized()) return false;

  try {
    const projectTempDir = resolveCurrentProjectTempDir();
    if (!projectTempDir) return false;

    const chatsDir = path.join(projectTempDir, 'chats');
    const entries = fs.readdirSync(chatsDir, { withFileTypes: true });
    return entries.some((entry) => entry.isFile() && /^session-.*\.json$/i.test(entry.name));
  } catch {
    return false;
  }
}

function makeFreshSessionPrepSkippedResult(reason = '') {
  return {
    requested: false,
    cleared: false,
    removedPathCount: 0,
    projectIdentifier: '',
    reason,
  };
}

function prepareFreshWorkspaceSessionForPromptLaunch() {
  if (!GEMINI_INITIAL_PROMPT) {
    return makeFreshSessionPrepSkippedResult();
  }

  const registryPath = path.join(ISO_HOME, '.gemini', 'projects.json');
  const workspacePaths = currentWorkspaceProjectPathCandidates();
  const result = {
    requested: true,
    cleared: false,
    removedPathCount: 0,
    projectIdentifier: '',
    reason: '',
    registryPath,
  };

  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  } catch {
    result.reason = 'workspace session registry is unavailable';
    return result;
  }

  if (!isPlainObject(parsed?.projects)) {
    result.reason = 'workspace session registry has no projects map';
    return result;
  }

  const nextProjects = { ...parsed.projects };
  const removedKeys = [];

  for (const candidate of workspacePaths) {
    const identifier = nextProjects[candidate];
    if (typeof identifier !== 'string' || !identifier.trim()) continue;
    delete nextProjects[candidate];
    removedKeys.push(candidate);
    if (!result.projectIdentifier) {
      result.projectIdentifier = identifier.trim();
    }
  }

  if (removedKeys.length === 0) {
    result.reason = 'no existing workspace session mapping';
    return result;
  }

  parsed.projects = nextProjects;

  try {
    fs.mkdirSync(path.dirname(registryPath), { recursive: true });
    fs.writeFileSync(registryPath, `${JSON.stringify(parsed, null, 2)}\n`, 'utf8');
  } catch {
    result.reason = 'failed to rewrite workspace session registry';
    return result;
  }

  result.cleared = true;
  result.removedPathCount = removedKeys.length;
  return result;
}

function resolveCurrentProjectTempDir() {
  const projectIdentifier = lookupProjectIdentifierForCurrentWorkspace();
  if (!projectIdentifier) return '';
  return path.join(ISO_HOME, '.gemini', 'tmp', projectIdentifier);
}

function lookupProjectIdentifierForCurrentWorkspace() {
  const registryPath = path.join(ISO_HOME, '.gemini', 'projects.json');

  try {
    const parsed = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
    const projects = parsed?.projects;
    if (!projects || typeof projects !== 'object') return '';

    for (const candidate of currentWorkspaceProjectPathCandidates()) {
      const identifier = projects[candidate];
      if (typeof identifier === 'string' && identifier.trim()) {
        return identifier.trim();
      }
    }
  } catch {
    return '';
  }

  return '';
}

function currentWorkspaceProjectPathCandidates() {
  const candidates = new Set();
  const cwd = process.cwd();
  if (!cwd) return [];

  candidates.add(cwd);
  candidates.add(path.resolve(cwd));
  try {
    candidates.add(fs.realpathSync.native(cwd));
  } catch {
    // ignore
  }

  for (const candidate of [...candidates]) {
    const alternate = alternateWorkspacePathAlias(candidate);
    if (alternate) {
      candidates.add(alternate);
      candidates.add(path.resolve(alternate));
    }
  }

  return [...candidates].filter(Boolean);
}

function alternateWorkspacePathAlias(candidate) {
  const value = String(candidate || '').trim();
  if (!value) return '';
  if (value === '/private') return '/';
  if (value.startsWith('/private/')) {
    return value.slice('/private'.length);
  }
  if (value.startsWith('/var/')) {
    return `/private${value}`;
  }
  return '';
}

function buildLaunchPlan(wrapperInfo, launchArgs) {
  if (WRAPPER_LAUNCH_MODE === 'shell') return makeShellLaunchPlan(wrapperInfo, launchArgs);
  if (WRAPPER_LAUNCH_MODE === 'direct') return makeDirectLaunchPlan(wrapperInfo, launchArgs);

  if (wrapperInfo.kind === 'script' || wrapperInfo.hasCRLFShebang || !wrapperInfo.isExecutable) {
    return makeShellLaunchPlan(wrapperInfo, launchArgs);
  }

  return makeDirectLaunchPlan(wrapperInfo, launchArgs);
}

function maybeBuildFallbackLaunchPlan(error, wrapperInfo, launchArgs, currentPlan) {
  if (currentPlan.mode === 'shell') return null;
  const message = error instanceof Error ? error.message : String(error);
  if (/posix_spawnp failed/i.test(message) || /ENOENT|EACCES|ENOEXEC/i.test(message)) {
    return makeShellLaunchPlan(wrapperInfo, launchArgs);
  }
  return null;
}

function makeDirectLaunchPlan(wrapperInfo, launchArgs) {
  return {
    mode: 'direct',
    file: wrapperInfo.execPath,
    args: launchArgs,
  };
}

function makeShellLaunchPlan(wrapperInfo, launchArgs) {
  const executable = wrapperInfo.execPath || GEMINI_WRAPPER_ENV;
  const command = ['exec', shQuote(executable), ...launchArgs.map(shQuote)].join(' ');
  return {
    mode: 'shell',
    file: SHELL_EXECUTABLE,
    args: ['-c', command],
  };
}

function inspectCommandTarget(command, pathEnv) {
  const result = {
    requested: command,
    resolvedPath: null,
    realPath: null,
    execPath: command,
    exists: false,
    isExecutable: false,
    kind: 'unknown',
    shebang: '',
    hasCRLFShebang: false,
    readError: '',
  };

  const resolved = resolveExecutableDetailed(command, pathEnv);
  result.resolvedPath = resolved.resolvedPath;
  result.realPath = resolved.realPath;
  result.execPath = resolved.resolvedPath || command;
  result.exists = resolved.exists;
  result.isExecutable = resolved.isExecutable;

  if (!resolved.exists || !resolved.resolvedPath) return result;

  try {
    const inspectPath = resolved.realPath || resolved.resolvedPath;
    const stat = fs.statSync(inspectPath);
    if (stat.isDirectory()) {
      result.kind = 'directory';
      return result;
    }

    const sample = fs.readFileSync(inspectPath, { encoding: 'utf8', flag: 'r' }).slice(0, 512);
    const firstLine = sample.split('\n', 1)[0] || '';
    const ext = path.extname(inspectPath).toLowerCase();

    if (firstLine.startsWith('#!')) {
      result.kind = 'script';
      result.shebang = firstLine.replace(/\r$/, '');
      result.hasCRLFShebang = /\r$/.test(firstLine);
      return result;
    }

    if (['.sh', '.bash', '.zsh', '.command', '.mjs', '.js'].includes(ext)) {
      result.kind = 'script';
      return result;
    }

    result.kind = /^[\x00-\x7F]*$/.test(sample) ? 'text' : 'binary';
  } catch (error) {
    result.readError = error instanceof Error ? error.message : String(error);
  }

  return result;
}

function resolveExecutableDetailed(cmd, pathEnv) {
  const result = { resolvedPath: null, realPath: null, exists: false, isExecutable: false };
  if (!cmd) return result;

  if (cmd.includes(path.sep)) {
    result.resolvedPath = cmd;
    result.exists = fs.existsSync(cmd);
    if (result.exists) {
      try {
        result.realPath = fs.realpathSync.native(cmd);
      } catch {
        result.realPath = cmd;
      }
      try {
        fs.accessSync(cmd, fs.constants.X_OK);
        result.isExecutable = true;
      } catch {
        result.isExecutable = false;
      }
    }
    return result;
  }

  for (const dir of (pathEnv || '').split(path.delimiter)) {
    if (!dir) continue;
    const candidate = path.join(dir, cmd);
    if (!fs.existsSync(candidate)) continue;
    result.resolvedPath = candidate;
    result.exists = true;
    try {
      result.realPath = fs.realpathSync.native(candidate);
    } catch {
      result.realPath = candidate;
    }
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      result.isExecutable = true;
    } catch {
      result.isExecutable = false;
    }
    return result;
  }

  return result;
}

function resolveExecutable(cmd) {
  const pathEnv = process.env.PATH || '';
  return resolveExecutableDetailed(cmd, pathEnv).resolvedPath || cmd;
}

function wrapSpawnError(error, wrapperInfo, launchPlan) {
  const parts = [
    error instanceof Error ? error.stack || error.message : String(error),
    '',
    `Launch mode: ${launchPlan.mode}`,
    `Launch file: ${launchPlan.file}`,
    `Launch args: ${JSON.stringify(launchPlan.args)}`,
    `Requested wrapper: ${GEMINI_WRAPPER_ENV}`,
    `Resolved wrapper: ${wrapperInfo.resolvedPath || '(not found)'}`,
    `Exists: ${wrapperInfo.exists}`,
    `Executable: ${wrapperInfo.isExecutable}`,
    `Kind: ${wrapperInfo.kind}`,
  ];

  if (wrapperInfo.shebang) parts.push(`Shebang: ${wrapperInfo.shebang}${wrapperInfo.hasCRLFShebang ? ' [CRLF detected]' : ''}`);
  if (!wrapperInfo.exists) parts.push('Hint: wrapper not found. Check GEMINI_WRAPPER and PATH.');
  else if (!wrapperInfo.isExecutable) parts.push('Hint: wrapper exists but is not executable. Try chmod +x <wrapper>.');
  else if (wrapperInfo.hasCRLFShebang) parts.push('Hint: wrapper shebang has CRLF. Convert it to LF.');
  else if (wrapperInfo.kind === 'script') parts.push('Hint: script wrappers are more reliable through clean shell exec mode.');

  return new Error(parts.join('\n'));
}

function logLaunchBanner({
  model,
  canResume,
  wrapperInfo,
  launchPlan,
  hasInitialPrompt,
  launchesWithInitialPrompt,
  geminiCliCapabilities,
  compatibilitySystemSettingsPath,
  startupPipelineQueued,
  startupStatsBlockedReason,
  startupStatsBlocksInitialPrompt,
  freshSessionReset,
}) {
  const modelLabel = MODEL_AUTO
    ? `Gemini CLI ${GEMINI_AUTO_MODEL}${model ? ` (fallback chain starts at ${model})` : ''}`
    : model;
  const lines = [
    `\n[${FLAVOR_LABEL}] Launching model: ${modelLabel}${canResume ? ' (resuming latest)' : ' (fresh)'}${RAW_OUTPUT ? ' [raw-output]' : ''}`,
    `[${FLAVOR_LABEL}] Flavor: ${CLI_FLAVOR}`,
    `[${FLAVOR_LABEL}] Runner path: ${RUNNER_PATH}`,
    `[${FLAVOR_LABEL}] Runner build: ${RUNNER_BUILD_ID}`,
    `[${FLAVOR_LABEL}] ISO home: ${ISO_HOME}`,
    `[${FLAVOR_LABEL}] Wrapper request: ${GEMINI_WRAPPER_ENV}`,
    `[${FLAVOR_LABEL}] Wrapper resolved: ${wrapperInfo.resolvedPath || '(not found on PATH yet)'}${wrapperInfo.exists ? '' : ' [missing]'}`,
    `[${FLAVOR_LABEL}] Wrapper kind: ${wrapperInfo.kind}`,
    `[${FLAVOR_LABEL}] Launch mode: ${launchPlan.mode}`,
    `[${FLAVOR_LABEL}] Shell fallback executable: ${SHELL_EXECUTABLE}`,
    `[${FLAVOR_LABEL}] Auto-continue mode: ${AUTO_CONTINUE_MODE}`,
    `[${FLAVOR_LABEL}] Auto-approve session permissions: ${AUTO_ALLOW_SESSION_PERMISSIONS ? 'ON' : 'OFF'}`,
    `[${FLAVOR_LABEL}] PTY backend: ${loadedPtyModuleName ?? 'none'}`,
  ];

  if (geminiCliCapabilities?.version) {
    lines.push(`[${FLAVOR_LABEL}] Gemini CLI version: ${geminiCliCapabilities.version}`);
  }
  if (compatibilitySystemSettingsPath && geminiCliCapabilities?.systemSettingsOverrideReason) {
    lines.push(`[${FLAVOR_LABEL}] Gemini CLI compatibility override: ${geminiCliCapabilities.systemSettingsOverrideReason}`);
  }
  if (freshSessionReset?.requested) {
    if (freshSessionReset.cleared) {
      lines.push(`[${FLAVOR_LABEL}] Fresh session prep: cleared prior workspace session binding (${freshSessionReset.removedPathCount} path alias${freshSessionReset.removedPathCount === 1 ? '' : 'es'})`);
    } else {
      lines.push(`[${FLAVOR_LABEL}] Fresh session prep: ${freshSessionReset.reason || 'no prior workspace session binding was cleared'}`);
    }
  }
  if (hasInitialPrompt && startupStatsBlockedReason && startupStatsBlocksInitialPrompt) {
    lines.push(`[${FLAVOR_LABEL}] Initial prompt delivery: blocked until startup ${startupPromptGateLabel()} completes`);
  } else if (launchesWithInitialPrompt) {
    lines.push(`[${FLAVOR_LABEL}] Initial prompt delivery: launch args (--prompt-interactive)`);
  } else if (hasInitialPrompt && startupPipelineQueued) {
    lines.push(`[${FLAVOR_LABEL}] Initial prompt delivery: queued after startup ${startupPromptDeliveryQueueLabel()}`);
  } else if (hasInitialPrompt) {
    lines.push(`[${FLAVOR_LABEL}] Initial prompt delivery: queued after prompt readiness`);
  }
  if (startupStatsBlockedReason && startupStatsBlocksInitialPrompt) {
    lines.push(`[${FLAVOR_LABEL}] Startup sequence: blocked (${startupStatsBlockedReason})`);
  } else if (startupStatsBlockedReason) {
    lines.push(`[${FLAVOR_LABEL}] Startup session stats: unavailable (${startupStatsBlockedReason})`);
  } else if (startupPipelineQueued) {
    lines.push(`[${FLAVOR_LABEL}] Startup sequence: queued (${startupSequenceQueuedLabel()})`);
  } else if (geminiCliCapabilities?.startupStatsAutomationDisabledReason) {
    lines.push(`[${FLAVOR_LABEL}] Startup session stats: skipped (${geminiCliCapabilities.startupStatsAutomationDisabledReason})`);
  }
  if (loadedPty) {
    lines.push(`[${FLAVOR_LABEL}] Local controls: ${hotkeySummary()}`);
  }
  if (wrapperInfo.kind === 'script' && wrapperInfo.shebang) {
    lines.push(`[${FLAVOR_LABEL}] Script shebang: ${wrapperInfo.shebang}${wrapperInfo.hasCRLFShebang ? ' [CRLF detected]' : ''}`);
  }
  if (QUIET_CHILD_NODE_WARNINGS) {
    lines.push(`[${FLAVOR_LABEL}] Child Node warnings: suppressed`);
  }
  if (DEBUG_LAUNCH) {
    lines.push(`[${FLAVOR_LABEL}] Launch file: ${launchPlan.file}`);
    lines.push(`[${FLAVOR_LABEL}] Launch args: ${JSON.stringify(launchPlan.args)}`);
    if (compatibilitySystemSettingsPath) {
      lines.push(`[${FLAVOR_LABEL}] Compatibility system settings: ${compatibilitySystemSettingsPath}`);
    }
  }

  console.error(lines.join('\n') + '\n');
}

function startupPipelineLabel() {
  return [STARTUP_CLEAR_COMMAND, STARTUP_STATS_COMMAND, STARTUP_MODEL_COMMAND]
    .map((value) => String(value || '').trim())
    .filter(Boolean)
    .join(' -> ');
}

function startupPromptGateLabel() {
  return String(STARTUP_CLEAR_COMMAND || '').trim() || 'prompt readiness';
}

function startupPromptDeliveryQueueLabel() {
  const gate = startupPromptGateLabel();
  const telemetry = [STARTUP_STATS_COMMAND, STARTUP_MODEL_COMMAND]
    .map((value) => String(value || '').trim())
    .filter(Boolean)
    .join(' -> ');
  return telemetry ? `${gate}; telemetry ${telemetry} best effort` : gate;
}

function startupSequenceQueuedLabel() {
  const pipeline = startupPipelineLabel();
  const hasBestEffortTelemetry = Boolean(String(STARTUP_STATS_COMMAND || '').trim() || String(STARTUP_MODEL_COMMAND || '').trim());
  if (!pipeline) return 'prompt readiness';
  return hasBestEffortTelemetry ? `${pipeline}; telemetry best effort` : pipeline;
}

function handleTerminalData(runId, chunk) {
  lastHeartbeat = Date.now();
  lastTerminalDataAt = Date.now();
  screenModel?.feed(chunk);

  rawTail += chunk;
  if (rawTail.length > RAW_TAIL_MAX) rawTail = rawTail.slice(-RAW_TAIL_MAX);
  normalizedTail = normalizeTerminalText(rawTail);
  if (normalizedTail.length > NORMALIZED_TAIL_MAX) normalizedTail = normalizedTail.slice(-NORMALIZED_TAIL_MAX);
  captureStartupStatsObservation();
  captureStartupModelCapacityObservation();

  if (/no\s+previous\s+sessions\s+found/i.test(normalizedTail)) {
    sawNoResumeSession = true;
  }

  detectBlockingBanners();
  detectApiErrorUsageLimit();

  const snapshot = detectCurrentSnapshot();
  updateCurrentSnapshot(snapshot);
  maybeAutomate(runId, snapshot);
}

let lastDetectedApiUsageLimitFingerprint = '';
function detectApiErrorUsageLimit() {
  if (lastSafetyNetAdvanceAt > 0 && Date.now() - lastSafetyNetAdvanceAt < SAFETY_NET_DEBOUNCE_MS) return;
  if (lastCapacityAt > 0 && Date.now() - lastCapacityAt < SAFETY_NET_DEBOUNCE_MS) return;
  if (lastExistingUsageLimitHandlerAt > 0 && Date.now() - lastExistingUsageLimitHandlerAt < SAFETY_NET_DEBOUNCE_MS) return;
  if (currentSnapshot?.kind === 'usage_limit' || currentSnapshot?.kind === 'capacity_menu') return;

  const tail = normalizedTail.slice(-4000);
  const apiErrorMatch = /api\s+error[^\]]*exhausted\s+your\s+capacity\s+on\s+this\s+model/i.test(tail)
    || /api\s+error[^\]]*quota\s+will\s+reset\s+after/i.test(tail);
  if (!apiErrorMatch) return;

  const usageLimitModelInTail = usageLimitModelFromLines(tail.split('\n'));
  if (usageLimitModelInTail && !modelIdentifiersMatch(usageLimitModelInTail, currentModel())) {
    return;
  }

  const resetMatch = tail.match(/quota\s+will\s+reset\s+after\s+([0-9hms\s]+)/i);
  const fingerprint = `${usageLimitModelInTail || currentModel()}:${resetMatch ? resetMatch[1].trim() : 'no-reset'}`;
  if (fingerprint === lastDetectedApiUsageLimitFingerprint) return;
  lastDetectedApiUsageLimitFingerprint = fingerprint;

  const stuckKinds = new Set(['stats-session', 'model-manage-open', 'model-manage-route', 'model-manage-finalize']);
  if (pendingPromptCommand) {
    if (stuckKinds.has(String(pendingPromptCommand.kind || ''))) {
      console.error(`\n[${FLAVOR_LABEL}] Dropping stuck ${pendingPromptCommand.kind} pending command before usage-limit recovery.\n`);
      pendingPromptCommand = null;
      clearPromptCommandTimer();
      clearPendingPromptCommandNudgeTimer();
      clearMenuPlan();
    } else {
      return;
    }
  }

  clearContinueTimer();
  clearPromptCommandTimer();
  continueLoopArmed = false;
  pendingPostUsageLimitAdvance = {
    reason: `Usage limit reached on ${currentModel()} (API error)`,
    usageLimitModel: currentModel(),
    armedAt: Date.now(),
  };
  if (DEBUG_AUTOMATION) {
    console.error(`[${FLAVOR_LABEL}][prompt] armed post-usage-limit advance from API error (${fingerprint})`);
  }
  if (!automationEnabled && AUTO_DISABLE_ON_USAGE_LIMIT) {
    setAutomationEnabled(true, 'usage_limit_recovery');
  }

}

function captureStartupStatsObservation() {
  if (startupStatsObserved) return;

  const visibleText = currentVisibleTerminalText();
  const snapshot = extractStartupStatsSnapshot(visibleText);
  if (!snapshot) return;

  startupStatsObserved = true;
  startupStatsSnapshot = snapshot;
}

function captureStartupModelCapacityObservation() {
  if (startupModelCapacityObserved) return;

  const visibleText = currentVisibleTerminalText();
  const snapshot = extractStartupModelCapacitySnapshot(visibleText);
  if (!snapshot) return;
  if (!MODEL_AUTO && (!Array.isArray(snapshot.rows) || snapshot.rows.length === 0) && !snapshot.currentModel) return;

  startupModelCapacityObserved = true;
  startupModelCapacitySnapshot = snapshot;
}

function currentScreenTerminalText() {
  return screenModel?.renderText(SCREEN_CAPTURE_LINES) || '';
}

function currentVisibleTerminalText() {
  return [
    currentScreenTerminalText(),
    normalizedTail,
  ].join('\n');
}

function setStartupStatsBlocked(reason, options = {}) {
  const cleanedReason = String(reason || '').trim();
  if (!cleanedReason) return false;
  const blocksInitialPrompt = options.blocksInitialPrompt !== false;
  if (startupStatsBlockedReason === cleanedReason && startupStatsBlocksInitialPrompt === blocksInitialPrompt) return false;

  startupStatsBlockedReason = cleanedReason;
  startupStatsBlocksInitialPrompt = blocksInitialPrompt;
  pendingPromptCommand = null;
  clearPromptCommandTimer();

  if (blocksInitialPrompt) {
    sentInitialPrompt = false;
    continueLoopArmed = false;
    clearInitialPromptTimer();
  }

  if (options.emitBanner !== false) {
    if (blocksInitialPrompt) {
      console.error(`\n[${FLAVOR_LABEL}] Startup sequence: blocked (${cleanedReason})`);
      console.error(`[${FLAVOR_LABEL}] Initial prompt delivery: blocked until startup ${startupPromptGateLabel()} completes.\n`);
    } else {
      console.error(`\n[${FLAVOR_LABEL}] Startup session stats: unavailable (${cleanedReason}) — continuing startup telemetry.\n`);
    }
  }

  return true;
}

function detectBlockingBanners() {
  const liveScreenText = screenModel?.renderText(SCREEN_CAPTURE_LINES) || '';
  const screenText = liveScreenText + '\n' + normalizedTail;

  const waitingForAuth = hasLiveAuthWait(liveScreenText, normalizedTail);
  if (waitingForAuth) {
    if (authWaitSince === 0) authWaitSince = Date.now();
    if (!warnedAuthWait && Date.now() - authWaitSince >= AUTH_WAIT_WARN_MS) {
      warnedAuthWait = true;
      console.error('[gemini-' + CLI_FLAVOR + '-pty] ⚠ Stuck on "Waiting for auth…" for >' + Math.round(AUTH_WAIT_WARN_MS / 1000) + 's. Complete the Google sign-in in your browser, or press Ctrl-C and relaunch. If the browser never opened, check that the CLI can reach https://accounts.google.com.');
    }
  } else {
    authWaitSince = 0;
    warnedAuthWait = false;
  }

  if (!warnedPolicyBanner &&
      /(restricting\s+models\s+for\s+free\s+tier|geminicli-updates|upgrade\s+to\s+a\s+supported\s+paid\s+plan)/i.test(screenText)) {
    warnedPolicyBanner = true;
    avoidProModelsForSession = true;
    const current = MODELS[modelIndex] || '(unknown)';
    const currentIsPro = /pro/i.test(current);
    const nextNonProIndex = findNextEligibleModelIndex(modelIndex);

    if (currentIsPro && nextNonProIndex >= 0 && !NEVER_SWITCH) {
      const target = MODELS[nextNonProIndex];
      console.error('[gemini-' + CLI_FLAVOR + '-pty] ⚠ Free-tier policy banner detected on "' + current + '" — auto-switching to "' + target + '".');
      if (activePty && queueDirectModelSwitchCommand(nextNonProIndex, 'Free-tier policy banner detected')) {
        scheduleStaticRecheck(QUICK_RECHECK_MS);
      } else {
        modelIndex = nextNonProIndex;
        requestLauncherAction('restart');
      }
    } else {
      const tierSafe = MODELS.filter((m) => !/pro/i.test(m));
      const hint = tierSafe.length > 0
        ? 'Free-tier-compatible models in your chain: ' + tierSafe.join(', ') + '.'
        : 'Your MODEL_CHAIN has no non-pro fallback — add gemini-3-flash-preview.';
      const extra = NEVER_SWITCH ? ' (NEVER_SWITCH is set — not auto-switching.)' : '';
      console.error('[gemini-' + CLI_FLAVOR + '-pty] ⚠ Gemini CLI is showing the free-tier policy banner. Current model: ' + current + '. ' + hint + extra);
    }
  }
}

function hasLiveAuthWait(liveScreenText, fallbackTailText = '') {
  const live = String(liveScreenText || '').trim();
  if (live) {
    return /waiting\s+for\s+auth(?:entication)?\b/i.test(live);
  }

  return /waiting\s+for\s+auth(?:entication)?\b/i.test(String(fallbackTailText || ''));
}

function hasAuthRestartRequiredPrompt(text) {
  const normalized = normalizeTerminalText(text).replace(/\s+/g, ' ').trim();
  if (!normalized) return false;
  return /authentication\s+succeeded/i.test(normalized)
    && /needs\s+to\s+be\s+restarted/i.test(normalized)
    && /press\s+r\s+to\s+restart/i.test(normalized);
}

function normalizeTerminalText(input) {
  const trimmed = stripTrailingIncompleteEscape(input);
  let text = trimmed
    .replace(/\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)/g, '')
    .replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/\u001B[PX^_][\s\S]*?(?:\u0007|\u001B\\)/g, '')
    .replace(/\u001B[@-_]/g, '')
    .replace(/\r\n?/g, '\n');

  const out = [];
  for (const char of text) {
    if (char === '\b') {
      out.pop();
      continue;
    }
    if (char === '\u0000') continue;
    out.push(char);
  }

  return out.join('').replace(/[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}

function stripTrailingIncompleteEscape(text) {
  const lastEsc = text.lastIndexOf('\u001B');
  if (lastEsc < 0) return text;
  const suffix = text.slice(lastEsc);
  if (isCompleteEscapeSequence(suffix)) return text;
  return text.slice(0, lastEsc);
}

function isCompleteEscapeSequence(suffix) {
  if (!suffix.startsWith('\u001B')) return true;
  if (suffix === '\u001B') return false;

  if (suffix.startsWith('\u001B[')) {
    return /\u001B\[[0-?]*[ -/]*[@-~]$/.test(suffix);
  }

  if (suffix.startsWith('\u001B]')) {
    return /(?:\u0007|\u001B\\)$/.test(suffix);
  }

  if (suffix.startsWith('\u001BP') || suffix.startsWith('\u001B^') || suffix.startsWith('\u001B_')) {
    return /(?:\u0007|\u001B\\)$/.test(suffix);
  }

  return suffix.length >= 2;
}

function detectCurrentSnapshot() {
  const screenText = screenModel?.renderText(SCREEN_CAPTURE_LINES) || '';
  const screenSnapshot = detectSnapshotFromText(screenText, 'screen');
  if (screenSnapshot.kind !== 'normal') return screenSnapshot;

  const rawSnapshot = detectSnapshotFromText(normalizedTail.slice(-NORMALIZED_TAIL_MAX), 'raw');
  const promptUsageLimitSnapshot = detectPromptUsageLimitSnapshotFromTail(screenSnapshot);
  if (rawSnapshot.kind !== 'normal') {
    if (screenSnapshot.chatPromptActive && isStaleRawSnapshotBehindPrompt(rawSnapshot)) {
      return promptUsageLimitSnapshot || screenSnapshot;
    }
    return rawSnapshot;
  }

  return promptUsageLimitSnapshot || screenSnapshot;
}

function isStaleRawSnapshotBehindPrompt(snapshot) {
  if (snapshot?.kind === 'usage_limit') {
    if (snapshot?.usageLimitPromptActive && usageLimitSnapshotMatchesVisibleModel(snapshot)) {
      return false;
    }
    return true;
  }

  return [
    'usage_limit',
    'capacity_menu',
    'capacity_continue',
    'capacity_info',
  ].includes(String(snapshot?.kind || ''));
}

function detectPromptUsageLimitSnapshotFromTail(screenSnapshot) {
  if (!screenSnapshot?.chatPromptActive) return null;

  const tailText = normalizedTail.slice(-NORMALIZED_TAIL_MAX);
  if (!hasUsageLimitSignal(tailText)) return null;

  const tailLines = tailText.split('\n');
  if (!hasChatPromptAfterUsageLimit(tailLines)) return null;
  const usageLimitModel = usageLimitModelFromLines(tailLines);
  if (usageLimitModel && !usageLimitSnapshotMatchesVisibleModel({ usageLimitModel })) {
    return null;
  }

  return makeSnapshot('usage_limit', 'tail', {
    reason: 'usage limit reached',
    fingerprint: fingerprintForUsageLimitEvent(tailLines),
    keepOption: null,
    keepOptionText: '',
    stopOption: null,
    stopOptionText: '',
    selectedOption: null,
    options: [],
    chatPromptActive: true,
    promptInputText: screenSnapshot.promptInputText || extractPromptInputText(tailLines),
    usageLimitPromptActive: true,
    usageLimitModel,
  });
}

function detectSnapshotFromText(text, source) {
  const rawLines = String(text || '').split('\n').slice(-SCREEN_CAPTURE_LINES).map((line) => line.replace(/\s+$/g, ''));
  const tail = rawLines.join('\n').slice(-NORMALIZED_TAIL_MAX);
  const menuBlocks = extractMenuBlocks(rawLines);
  const chatPromptActive = detectChatPromptActive(rawLines);
  const promptInputText = extractPromptInputText(rawLines);

  if (hasAuthRestartRequiredPrompt(tail) && !hasChatPromptAfterAuthRestartRequired(rawLines)) {
    return makeSnapshot('auth_restart_required', source, {
      reason: 'authentication succeeded; restart required',
      fingerprint: fingerprintFromLines(compactLines(tail), ['authentication succeeded', 'press r to restart']),
      chatPromptActive,
      promptInputText,
    });
  }

  const permissionBlock = findPermissionMenuBlock(rawLines, menuBlocks, chatPromptActive);
  if (permissionBlock) {
    const permissionChoice = resolvePermissionChoice(permissionBlock.options);
    if (permissionChoice) {
      return {
        kind: 'permission',
        source,
        reason: 'permission prompt',
        targetOption: permissionChoice,
        targetOptionText: permissionChoice.numberText,
        targetSelected: permissionChoice.selected,
        selectedOption: permissionBlock.selectedOption,
        fingerprint: fingerprintFromBlock(permissionBlock, ['action required', 'allow execution of', permissionChoice.canonical]),
        options: permissionBlock.options,
        blockStart: permissionBlock.start,
        blockEnd: permissionBlock.end,
        chatPromptActive,
        blockMode: permissionBlock.mode,
      };
    }
  }

  const trustBlock = findTrustFolderMenuBlock(rawLines, menuBlocks, chatPromptActive);
  if (trustBlock) {
    const trustOption = trustBlock.options.find((option) => option.canonical.startsWith('trust folder'));
    if (trustOption) {
      return {
        kind: 'trust_folder',
        source,
        reason: 'trust folder prompt',
        targetOption: trustOption,
        targetOptionText: trustOption.numberText,
        targetSelected: trustOption.selected,
        selectedOption: trustBlock.selectedOption,
        fingerprint: fingerprintFromBlock(trustBlock, ['do you trust this folder', 'trust folder', trustOption.canonical]),
        options: trustBlock.options,
        blockStart: trustBlock.start,
        blockEnd: trustBlock.end,
        chatPromptActive,
        blockMode: trustBlock.mode,
      };
    }
  }

  const modelManageRoutingBlock = findModelManageRoutingMenuBlock(rawLines, menuBlocks, chatPromptActive);
  if (modelManageRoutingBlock) {
    return {
      kind: 'model_manage_routing',
      source,
      reason: 'model manage routing',
      targetOption: modelManageRoutingBlock.manualOption,
      targetOptionText: modelManageRoutingBlock.manualOption?.numberText || '',
      selectedOption: modelManageRoutingBlock.selectedOption,
      fingerprint: fingerprintFromBlock(modelManageRoutingBlock, [
        'auto (gemini 3)',
        'auto (gemini 2.5)',
        'manual',
      ]),
      options: modelManageRoutingBlock.options,
      blockStart: modelManageRoutingBlock.start,
      blockEnd: modelManageRoutingBlock.end,
      chatPromptActive,
      blockMode: modelManageRoutingBlock.mode,
    };
  }

  const modelManageModelsBlock = findModelManageModelListBlock(rawLines, menuBlocks, chatPromptActive);
  if (modelManageModelsBlock) {
    const capacitySnapshot = extractStartupModelCapacitySnapshot(rawLines.join('\n'));
    return {
      kind: 'model_manage_models',
      source,
      reason: 'model manage models',
      modelOptions: modelManageModelsBlock.modelOptions,
      capacityRows: capacitySnapshot?.rows || [],
      selectedOption: modelManageModelsBlock.selectedOption,
      fingerprint: fingerprintFromBlock(modelManageModelsBlock, modelManageModelsBlock.modelOptions.map((option) => option.canonical)),
      options: modelManageModelsBlock.options,
      blockStart: modelManageModelsBlock.start,
      blockEnd: modelManageModelsBlock.end,
      chatPromptActive,
      blockMode: modelManageModelsBlock.mode,
    };
  }

  const recentLines = rawLines.slice(-Math.max(12, DIALOG_BOTTOM_WINDOW_LINES));
  const recentTail = recentLines.join('\n');
  const usageLimitBlock = findUsageLimitMenuBlock(rawLines, menuBlocks, chatPromptActive);
  const usagePatterns = usageLimitPatterns();
  if (usagePatterns.some((pattern) => pattern.test(recentTail))) {
    const keepOption = usageLimitBlock ? resolveCapacityKeepOption(usageLimitBlock.options) : null;
    const stopOption = usageLimitBlock ? resolveUsageLimitStopOption(usageLimitBlock.options) : null;
    const usageLimitModel = usageLimitModelFromLines(rawLines);
    return {
      kind: 'usage_limit',
      source,
      reason: 'usage limit reached',
      fingerprint: fingerprintForUsageLimitEvent(rawLines),
      keepOption,
      keepOptionText: keepOption?.numberText || '',
      stopOption,
      stopOptionText: stopOption?.numberText || '',
      selectedOption: usageLimitBlock?.selectedOption || null,
      options: usageLimitBlock?.options || [],
      blockStart: usageLimitBlock?.start,
      blockEnd: usageLimitBlock?.end,
      chatPromptActive,
      promptInputText,
      usageLimitPromptActive: hasChatPromptAfterUsageLimit(rawLines),
      usageLimitModel,
      blockMode: usageLimitBlock?.mode,
    };
  }

  const capacityPatterns = [
    /we\s+are\s+currently\s+experiencing\s+high\s+demand/i,
    /no\s+capacity\s+available/i,
    /high\s+demand\s+right\s+now/i,
    /currently\s+overloaded/i,
    /model\s+is\s+currently\s+overloaded/i,
    /temporarily\s+unavailable/i,
    /currently\s+experiencing/i,
    /\/model\s+to\s+switch\s+models/i,
    /appreciate\s+your\s+patience/i,
  ];

  const hasCapacity = capacityPatterns.some((pattern) => pattern.test(recentTail));
  const normalizedRecentTail = normalizeLabel(recentTail);

  const capacityBlock = hasCapacity
    ? (findCapacityMenuBlock(rawLines, menuBlocks, chatPromptActive)
      || findFallbackCapacityMenuBlock(rawLines, chatPromptActive, normalizedRecentTail))
    : null;
  if (capacityBlock) {
    const keepOption = resolveCapacityKeepOption(capacityBlock.options);
    const switchOption = resolveCapacitySwitchOption(capacityBlock.options);
    const stopOption = findMenuOption(capacityBlock.options, STOP_LABELS);
    if (keepOption) {
      return {
        kind: 'capacity_menu',
        source,
        reason: 'capacity menu',
        keepOption,
        keepOptionText: keepOption.numberText,
        keepSelected: keepOption.selected,
        switchOption: switchOption || null,
        switchOptionText: switchOption?.numberText || '',
        stopOptionText: stopOption?.numberText || '',
        selectedOption: capacityBlock.selectedOption,
        fingerprint: fingerprintFromBlock(capacityBlock, [
          keepOption.canonical,
          switchOption?.canonical || '',
          stopOption?.canonical || '',
          'high demand',
          'no capacity',
        ]),
        options: capacityBlock.options,
        blockStart: capacityBlock.start,
        blockEnd: capacityBlock.end,
        chatPromptActive,
        blockMode: capacityBlock.mode,
      };
    }
  }

  const continuePrompt = detectContinuePrompt(recentTail);
  if (continuePrompt) {
    return {
      kind: 'capacity_continue',
      source,
      reason: continuePrompt.reason,
      continueAction: continuePrompt.action,
      continueDelayMs: continuePrompt.delayMs ?? null,
      fingerprint: fingerprintFromLines(compactLines(recentTail), [continuePrompt.anchor]),
      options: [],
      chatPromptActive,
    };
  }

  if (!hasCapacity) {
    const promptContext = buildPromptContext(rawLines);
    return makeSnapshot('normal', source, {
      chatPromptActive,
      promptContext,
      promptFingerprint: promptContext,
      promptInputText,
    });
  }

  return {
    kind: 'capacity_info',
    source,
    reason: 'capacity info',
    fingerprint: fingerprintFromLines(compactLines(recentTail), ['high demand', 'no capacity']),
    options: [],
    chatPromptActive,
  };
}

function findFallbackCapacityMenuBlock(rawLines, chatPromptActive, normalizedRecentTail) {
  const recentWindow = rawLines.slice(-Math.max(14, DIALOG_CONTEXT_LINES));
  const hasRecentCapacityContext = Boolean(
    normalizedRecentTail.includes('high demand') ||
    normalizedRecentTail.includes('no capacity') ||
    normalizedRecentTail.includes('temporarily unavailable') ||
    normalizedRecentTail.includes('currently experiencing') ||
    normalizedRecentTail.includes('switch models') ||
    normalizedRecentTail.includes('overloaded')
  );
  if (!hasRecentCapacityContext) {
    return null;
  }

  const indexedOptions = [];

  for (let index = 0; index < recentWindow.length; index += 1) {
    const absoluteIndex = rawLines.length - recentWindow.length + index;
    const option = parseOptionLine(recentWindow[index], absoluteIndex);
    if (!option) {
      continue;
    }

    indexedOptions.push(option);
  }

  if (indexedOptions.length < 2) {
    return null;
  }

  const options = indexedOptions.filter((option) => option.numberText);
  if (options.length < 2) {
    return null;
  }

  if (!isActionableDialogBlock({ end: options.at(-1).index, options }, rawLines.length, chatPromptActive)) {
    return null;
  }

  const first = options[0].index;
  const last = options.at(-1).index;
  const start = Math.max(0, first - 2);
  const end = Math.min(rawLines.length - 1, last + 2);
  const contextLines = rawLines.slice(start, end + 1);
  const context = contextLines.map((line) => normalizeLabel(line)).join(' | ');

  if (
    !hasRecentCapacityContext &&
    !context.includes('high demand') &&
    !context.includes('no capacity') &&
    !context.includes('temporarily unavailable') &&
    !context.includes('currently experiencing') &&
    !context.includes('switch models')
  ) {
    return null;
  }

  const selectedOption = options.find((option) => option.selected) || null;
  return {
    start,
    end,
    options,
    contextLines,
    selectedOption,
    mode: selectedOption ? 'radio' : 'plain',
  };
}

function usageLimitPatterns() {
  return [
    /you(?:'ve| have)\s+(?:reached|hit)\s+(?:your\s+)?(?:usage|quota|request|rate)\s+limit/i,
    /usage\s+limit\s+reached/i,
    /you(?:'ve| have)\s+exhausted\s+your\s+capacity\s+on\s+this\s+model/i,
    /quota\s+(?:reached|exceeded|used\s+up)/i,
    /quota\s+will\s+reset\s+after/i,
    /access\s+resets\s+at/i,
    /\/stats(?:\s+model)?\s+for\s+usage\s+details/i,
    /rate\s+limit\s+exceeded/i,
    /try\s+again\s+(?:later|tomorrow)/i,
    /come\s+back\s+(?:later|tomorrow)/i,
  ];
}

function hasUsageLimitSignal(text) {
  const value = String(text || '');
  if (!value) return false;
  return usageLimitPatterns().some((pattern) => pattern.test(value));
}

function findLastUsageLimitAnchorIndex(rawLines) {
  const patterns = usageLimitPatterns();
  for (let index = rawLines.length - 1; index >= 0; index -= 1) {
    const line = String(rawLines[index] || '');
    if (patterns.some((pattern) => pattern.test(line))) return index;
  }
  return -1;
}

function hasChatPromptAfterUsageLimit(rawLines) {
  const promptIndex = findLastChatPromptIndex(rawLines);
  if (promptIndex < 0) return false;

  const usageIndex = findLastUsageLimitAnchorIndex(rawLines);
  return usageIndex >= 0 && promptIndex > usageIndex;
}

function findLastAuthRestartRequiredAnchorIndex(rawLines) {
  const lines = Array.isArray(rawLines)
    ? rawLines.map((line) => String(line || ''))
    : String(rawLines || '').split('\n');

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const line = normalizeTerminalText(lines[index]).replace(/\s+/g, ' ').trim();
    if (/press\s+r\s+to\s+restart/i.test(line) || /needs\s+to\s+be\s+restarted/i.test(line)) {
      return index;
    }
  }
  return -1;
}

function hasChatPromptAfterAuthRestartRequired(rawLines) {
  const promptIndex = findLastChatPromptIndex(rawLines);
  if (promptIndex < 0) return false;

  const authRestartIndex = findLastAuthRestartRequiredAnchorIndex(rawLines);
  return authRestartIndex >= 0 && promptIndex > authRestartIndex;
}

function usageLimitModelFromLines(rawLines) {
  const lines = Array.isArray(rawLines)
    ? rawLines.map((line) => String(line || ''))
    : String(rawLines || '').split('\n');
  const usageIndex = findLastUsageLimitAnchorIndex(lines);
  if (usageIndex < 0) return '';

  return extractVisibleCurrentModel(lines.slice(0, usageIndex + 1).join('\n'));
}

function fingerprintForUsageLimitEvent(rawLines) {
  const lines = Array.isArray(rawLines)
    ? rawLines.map((line) => String(line || '').replace(/\s+$/g, ''))
    : String(rawLines || '').split('\n').map((line) => line.replace(/\s+$/g, ''));
  const usageIndex = findLastUsageLimitAnchorIndex(lines);
  if (usageIndex < 0) {
    return fingerprintFromLines(compactLines(lines.join('\n')), ['usage limit', 'quota', 'rate limit', 'capacity', 'exhausted']);
  }

  const usageModel = usageLimitModelFromLines(lines);
  const contextStart = Math.max(0, usageIndex - 8);
  const contextEnd = Math.min(lines.length, usageIndex + 8);
  const contextLines = lines.slice(contextStart, contextEnd);
  const eventFingerprint = fingerprintFromLines(compactLines(contextLines.join('\n')), [
    'usage limit',
    'quota',
    'rate limit',
    'capacity',
    'exhausted',
    'reset',
    'access resets',
  ]);

  return [
    'usage-limit',
    normalizeModelIdentifier(usageModel),
    eventFingerprint,
  ].filter(Boolean).join('|');
}

function usageLimitSnapshotMatchesVisibleModel(snapshot) {
  if (snapshot?.ignoreVisibleModelMismatch === true) return true;
  const usageModel = String(snapshot?.usageLimitModel || '').trim();
  if (!usageModel) return true;

  const visibleModel = extractVisibleCurrentModel(currentScreenTerminalText())
    || extractVisibleCurrentModel(currentVisibleTerminalText());
  if (!visibleModel) return true;

  return modelIdentifiersMatch(usageModel, visibleModel);
}

function makeSnapshot(kind, source = 'none', extra = {}) {
  return {
    kind,
    source,
    reason: kind,
    fingerprint: `${source}:${kind}`,
    options: [],
    chatPromptActive: false,
    promptContext: '',
    promptFingerprint: '',
    ...extra,
  };
}

function compactLines(text) {
  const rawLines = String(text || '').split('\n').slice(-180);
  const out = [];
  for (const raw of rawLines) {
    const cleaned = raw.replace(/\s+/g, ' ').trim();
    if (!cleaned) continue;
    if (out[out.length - 1] === cleaned) continue;
    out.push(cleaned);
  }
  return out;
}

function parseOptionLine(rawLine, index) {
  const ansiCleaned = String(rawLine || '').replace(/\x1B\[[0-9;]*[A-Za-z]/gu, '').replace(/\s+$/g, '');
  if (!ansiCleaned) return null;

  const withoutBox = ansiCleaned.replace(/^[│║┃|\s]+/u, '').replace(/[│║┃|]\s*$/u, '');
  const selected = /^[•●◦○▪◆▶➜»›>*-]+\s*/u.test(withoutBox);
  const stripped = withoutBox.replace(/^[•●◦○▪◆▶➜»›>*-]+\s*/u, '').trim();
  const match = stripped.match(/^(\d+)\s*[.):-]?\s*(.+)$/u)
    || stripped.match(/^\[(\d+)\]\s*(.+)$/u)
    || stripped.match(/^(\d+)\s*\)\s*(.+)$/u)
    || stripped.match(/^(\d+)\s*-\s*(.+)$/u);
  if (!match) return null;

  const canonical = normalizeLabel(match[2]);
  if (!canonical) return null;

  return {
    index,
    numberText: match[1],
    label: match[2].trim(),
    canonical,
    raw: rawLine,
    selected,
  };
}

function extractMenuBlocks(rawLines) {
  const indexedOptions = [];
  for (let index = 0; index < rawLines.length; index += 1) {
    const option = parseOptionLine(rawLines[index], index);
    if (option) indexedOptions.push(option);
  }
  if (indexedOptions.length === 0) return [];

  const groups = [];
  let current = [indexedOptions[0]];
  for (let i = 1; i < indexedOptions.length; i += 1) {
    const prev = current[current.length - 1];
    const next = indexedOptions[i];
    if (next.index - prev.index <= 2) {
      current.push(next);
      continue;
    }
    groups.push(current);
    current = [next];
  }
  groups.push(current);

  return groups.map((options) => {
    const start = Math.max(0, options[0].index - DIALOG_CONTEXT_LINES);
    const end = Math.min(rawLines.length - 1, options[options.length - 1].index + DIALOG_CONTEXT_LINES);
    const contextLines = rawLines.slice(start, end + 1);
    const selectedOption = options.find((option) => option.selected) || null;
    return {
      start,
      end,
      options,
      contextLines,
      selectedOption,
      mode: selectedOption ? 'radio' : 'plain',
    };
  });
}

function normalizeLabel(text) {
  return String(text)
    .toLowerCase()
    .replace(/^[?]+\s*/, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function isChatPromptLine(rawLine) {
  const trimmed = String(rawLine || '').trim();
  if (/^>\s*$/.test(trimmed) || /^>\s+.+/.test(trimmed)) return true;
  if (/^[*•●◦○▪◆▶➜»›-]\s+\/\S+/u.test(trimmed)) return true;

  const normalized = normalizeLabel(trimmed.replace(/^[*•●◦○▪◆▶➜»›-]+\s*/u, ''));
  return normalized === 'type your message or @path/to/file' || normalized === 'type your message';
}

function detectChatPromptActive(rawLines) {
  const window = rawLines.slice(-Math.max(2, CHAT_PROMPT_WINDOW_LINES));
  return window.some((line) => isChatPromptLine(line));
}

function findLastChatPromptIndex(rawLines) {
  for (let index = rawLines.length - 1; index >= 0; index -= 1) {
    if (isChatPromptLine(rawLines[index])) {
      return index;
    }
  }
  return -1;
}

function extractPromptInputText(rawLines) {
  const window = (Array.isArray(rawLines) ? rawLines : []).slice(-Math.max(4, CHAT_PROMPT_WINDOW_LINES + 2));
  for (let index = window.length - 1; index >= 0; index -= 1) {
    const trimmed = cleanPromptInputLine(window[index]);
    if (!trimmed) continue;

    const match = trimmed.match(/^(?:>|[*•●◦○▪◆▶➜»›-])\s*(.*)$/u);
    if (!match) continue;

    const parts = [String(match[1] || '').trim()];
    for (let nextIndex = index + 1; nextIndex < window.length; nextIndex += 1) {
      const continuation = cleanPromptInputLine(window[nextIndex]);
      if (!continuation) continue;
      if (isChatPromptLine(continuation)) break;
      if (isDecorativePromptLine(continuation)) continue;
      if (isLikelyCommandOutputPromptText(continuation)) break;
      if (/^[*•●◦○▪◆▶➜»›-]\s+/u.test(continuation)) break;

      if (/^\/\S+/.test(continuation) || isAutomationPromptInputLine(continuation)) {
        parts.push(continuation.trim());
        continue;
      }
      break;
    }

    const text = parts.join('\n').trim();
    const normalized = normalizeLabel(text);
    if (!text) return '';
    if (normalized === 'type your message or @path/to/file' || normalized === 'type your message') return '';
    if (isLikelyCommandOutputPromptText(text)) return '';
    return text;
  }
  return '';
}

function cleanPromptInputLine(rawLine) {
  return normalizeTerminalText(String(rawLine || ''))
    .replace(/\s+$/g, '')
    .trim();
}

function isLikelyCommandOutputPromptText(text) {
  const trimmed = String(text || '')
    .replace(/\x1B\[[0-9;?]*[ -/]*[@-~]/gu, '')
    .trim();
  if (!trimmed) return false;
  if (/^[╭╰│┌└├┤┬┴┼─═║┃]/u.test(trimmed)) return true;

  const normalized = normalizeLabel(trimmed);
  if (!normalized) return false;
  return normalized.startsWith('session stats')
    || normalized.startsWith('interaction summary')
    || normalized.startsWith('select model')
    || normalized.startsWith('model usage')
    || normalized.startsWith('workspace (/directory)')
    || normalized.startsWith('gemini cli v')
    || normalized.startsWith('signed in with google')
    || normalized.startsWith('plan: gemini code assist');
}

function isDecorativePromptLine(rawLine) {
  const trimmed = String(rawLine || '').trim();
  if (!trimmed) return true;
  if (/^[\u2500-\u257F\u2580-\u259F\s]+$/u.test(trimmed)) return true;
  return false;
}

function buildPromptContext(rawLines) {
  const promptIndex = findLastChatPromptIndex(rawLines);
  if (promptIndex < 0) return '';

  const contextLines = rawLines.slice(Math.max(0, promptIndex - 12), promptIndex);
  const meaningful = [];

  for (const rawLine of contextLines) {
    if (isDecorativePromptLine(rawLine)) continue;
    const canonical = normalizeLabel(rawLine);
    if (!canonical) continue;
    if (canonical.includes('type your message or @path/to/file')) continue;
    if (canonical === '>') continue;
    meaningful.push(canonical);
  }

  return compactLines(meaningful.join('\n')).join(' | ');
}

function isBlockNearBottom(block, totalLines) {
  return block.end >= Math.max(0, totalLines - DIALOG_BOTTOM_WINDOW_LINES);
}

function isActionableDialogBlock(block, totalLines, chatPromptActive) {
  if (!isBlockNearBottom(block, totalLines)) return false;
  if (chatPromptActive && block.end < totalLines - 4) return false;
  return true;
}

function findPermissionMenuBlock(rawLines, blocks, chatPromptActive) {
  for (const block of blocks) {
    if (!isActionableDialogBlock(block, rawLines.length, chatPromptActive)) continue;
    const target = resolvePermissionChoice(block.options);
    if (!target) continue;

    const context = block.contextLines.map((line) => normalizeLabel(line)).join(' | ');
    const hasAnchor =
      context.includes('allow execution of') ||
      context.includes('action required') ||
      context.includes('toggle auto-edit') ||
      context.includes('tip: toggle auto-edit') ||
      context.includes('apply this change') ||
      context.includes('apply these changes') ||
      context.includes('modify with external editor');
    const hasSiblingPermissionOption = block.options.some((option) =>
      /allow once|suggest changes|allow for this session|allow this command for all future sessions|modify with external editor/.test(option.canonical)
    );
    const hasSelectionCue = Boolean(block.selectedOption) || /[•●◦○▪◆▶➜»›]/u.test(block.contextLines.join('\n'));

    if (hasAnchor && hasSiblingPermissionOption && hasSelectionCue) return block;
  }
  return null;
}

function resolvePermissionChoice(options) {
  if (!Array.isArray(options) || options.length === 0) return null;

  const configured = options.find((option) => option.canonical.includes(PERMISSION_OPTION_LABEL));
  if (configured) return configured;

  const explicit = options.find((option) => option.canonical.includes('allow this command for all future sessions'));
  if (explicit) return explicit;

  const preferred = options.find((option) => option.numberText === String(PERMISSION_OPTION_INDEX));
  if (preferred && containsPermissionSignal(preferred.canonical)) {
    return preferred;
  }

  const allowSession = options.find((option) => option.canonical.includes('allow for this session'));
  if (allowSession) return allowSession;

  const allowOnce = options.find((option) => option.canonical.includes('allow once'));
  if (allowOnce) return allowOnce;

  return null;
}

function containsPermissionSignal(optionText) {
  return /allow|permission|auto-save|future|command/.test(optionText);
}

function findTrustFolderMenuBlock(rawLines, blocks, chatPromptActive) {
  for (const block of blocks) {
    if (!isActionableDialogBlock(block, rawLines.length, chatPromptActive)) continue;

    const trustOption = block.options.find((option) => option.canonical.startsWith('trust folder'));
    if (!trustOption) continue;

    const context = block.contextLines.map((line) => normalizeLabel(line)).join(' | ');
    const hasAnchor =
      context.includes('do you trust this folder') &&
      context.includes('trusting a folder allows gemini to execute commands');
    const hasSibling = block.options.some((option) => option.canonical.startsWith('trust parent folder')) &&
      block.options.some((option) => option.canonical.includes("don't trust"));
    const hasSelectionCue = Boolean(block.selectedOption) || /[•●◦○▪◆▶➜»›]/u.test(block.contextLines.join('\n'));

    if (hasAnchor && hasSibling && hasSelectionCue) return block;
  }
  return null;
}

function findModelManageRoutingMenuBlock(rawLines, blocks, chatPromptActive) {
  for (const block of blocks) {
    if (!isActionableDialogBlock(block, rawLines.length, chatPromptActive)) continue;

    const manualOption = block.options.find((option) => option.canonical.startsWith('manual'));
    if (!manualOption) continue;

    const autoOptions = block.options.filter((option) => option.canonical.startsWith('auto (gemini'));
    if (autoOptions.length === 0) continue;

    const context = block.contextLines.map((line) => normalizeLabel(line)).join(' | ');
    const hasAnchor =
      context.includes('let gemini cli decide the best model for the task') ||
      context.includes('manually select a model') ||
      context.includes('remember model') ||
      context.includes('select your gemini cli model');
    if (hasAnchor || autoOptions.length >= 2) {
      return {
        ...block,
        manualOption,
      };
    }
  }

  return null;
}

function findModelManageModelListBlock(rawLines, blocks, chatPromptActive) {
  for (const block of blocks) {
    if (!isActionableDialogBlock(block, rawLines.length, chatPromptActive)) continue;

    const modelOptions = block.options
      .map((option) => {
        const modelIdentifier = extractGeminiModelIdentifier(option.label || option.canonical);
        const isAutoOption = /^auto \(gemini [^)]+\)/i.test(option.canonical);
        if (!modelIdentifier && !isAutoOption) return null;
        return {
          ...option,
          modelIdentifier: modelIdentifier || option.canonical,
        };
      })
      .filter(Boolean);
    if (modelOptions.length < 2) continue;

    const context = block.contextLines.map((line) => normalizeLabel(line)).join(' | ');
    const hasAnchor =
      context.includes('manual') ||
      context.includes('remember model') ||
      context.includes('select model') ||
      context.includes('available models');

    if (hasAnchor || modelOptions.length >= 3) {
      return {
        ...block,
        modelOptions,
      };
    }
  }

  return null;
}

function findCapacityMenuBlock(rawLines, blocks, chatPromptActive) {
  for (const block of blocks) {
    if (!isActionableDialogBlock(block, rawLines.length, chatPromptActive)) continue;

    const context = block.contextLines.map((line) => normalizeLabel(line)).join(' | ');
    const hasCapacityAnchor =
      context.includes('high demand') ||
      context.includes('no capacity') ||
      context.includes('temporarily unavailable') ||
      context.includes('currently experiencing') ||
      context.includes('switch models');
    const isVeryStrongAnchor = context.includes('experiencing high demand') || context.includes('no capacity available');
    const hasEnoughMenuDensity = block.options.length >= 2 || block.selectedOption !== null;

    if (isVeryStrongAnchor) return block;
    if (hasCapacityAnchor && hasEnoughMenuDensity) return block;
  }
  return null;
}

function findUsageLimitMenuBlock(rawLines, blocks, chatPromptActive) {
  for (const block of [...blocks].reverse()) {
    if (!isActionableDialogBlock(block, rawLines.length, chatPromptActive)) continue;

    const context = block.contextLines.map((line) => normalizeLabel(line)).join(' | ');
    const hasUsageAnchor =
      context.includes('usage limit reached') ||
      context.includes('quota will reset after') ||
      context.includes('access resets at') ||
      context.includes('/stats model for usage details') ||
      context.includes('/model to switch models');
    const keepOption = resolveCapacityKeepOption(block.options);
    const stopOption = resolveUsageLimitStopOption(block.options);

    if (hasUsageAnchor && keepOption && stopOption) return block;
  }
  return null;
}

function resolveCapacityKeepOption(options) {
  const matched = findMenuOption(options, KEEP_LABELS);
  if (matched) return matched;

  const explicitFirst = options.find((option) => option.numberText === '1');
  if (explicitFirst) return explicitFirst;

  return options[0] || null;
}

function resolveCapacitySwitchOption(options) {
  const matched = findMenuOption(options, SWITCH_LABELS);
  if (matched) return matched;

  const explicitSecond = options.find((option) => option.numberText === '2');
  const explicitStop = options.find((option) => option.numberText === '3') || findMenuOption(options, STOP_LABELS);

  if (explicitSecond && options.length >= 2 && explicitSecond !== explicitStop) {
    return explicitSecond;
  }

  if (options.length >= 3) {
    const nonStopOptions = options.filter((option) => option !== explicitStop);
    if (nonStopOptions.length >= 2) {
      return nonStopOptions[1];
    }
  }

  return null;
}

function resolveUsageLimitStopOption(options) {
  const matched = findMenuOption(options, STOP_LABELS);
  if (matched) return matched;

  const explicitSecond = options.find((option) => option.numberText === '2');
  if (explicitSecond && !isCapacityKeepOption(explicitSecond)) return explicitSecond;

  const lastOption = options.at(-1) || null;
  if (lastOption && !isCapacityKeepOption(lastOption)) return lastOption;

  return null;
}

function isCapacityKeepOption(option) {
  if (!option) return false;
  const canonical = String(option.canonical || '').trim();
  if (!canonical) return false;
  return KEEP_LABELS.map(normalizeLabel).filter(Boolean).some((label) => canonical === label || canonical.includes(label));
}

function findMenuOption(options, labels) {
  const normalizedLabels = labels.map(normalizeLabel).filter(Boolean);
  for (const option of options) {
    for (const label of normalizedLabels) {
      if (option.canonical === label) return option;
      if (option.canonical.includes(label)) return option;
    }
  }
  return null;
}

function detectContinuePrompt(tail) {
  const patterns = [
    {
      action: 'command',
      reason: 'context window warning',
      anchor: 'remaining context window limit',
      delayMs: 120,
      match:
        /sending\s+this\s+message\s*\(\s*[\d,]+\s+tokens?\s*\)\s+might\s+exceed\s+the\s+remaining\s+context\s+window(?:\s+limit)?\s*\(\s*[\d,]+\s+tokens?\s*\)/i,
    },
    {
      action: 'command',
      reason: 'continue prompt',
      anchor: 'type continue',
      match:
        /(?:(?:type|enter|send|write)\s+["'`]?continue["'`]?\s+(?:to|for)\b[^\n]*|(?:to|for)\s+(?:keep\s+trying|continue\s+waiting|retry)[^\n]*\btype\s+["'`]?continue["'`]?)/i,
    },
    {
      action: 'c',
      reason: 'type c prompt',
      anchor: "type 'c'",
      match: /type\s+["'`]?c["'`]?\s+to\s+continue/i,
    },
    {
      action: 'enter',
      reason: 'press any key prompt',
      anchor: 'press any key',
      match: /press\s+any\s+key\s+to\s+continue/i,
    },
    {
      action: 'enter',
      reason: 'press enter prompt',
      anchor: 'press enter',
      match:
        /(?:(?:press|hit)\s+(?:enter|return)\s+(?:to|for)\b[^\n]*(?:keep\s+trying|continue\s+waiting|retry|try\s+again)|(?:keep\s+trying|continue\s+waiting|retry|try\s+again)[^\n]*(?:press|hit)\s+(?:enter|return))/i,
    },
  ];

  for (const pattern of patterns) {
    if (pattern.match.test(tail)) return pattern;
  }
  return null;
}

function fingerprintFromLines(lines, anchors) {
  const usableAnchors = anchors.map((anchor) => normalizeLabel(anchor)).filter(Boolean);
  const selected = [];
  for (const line of lines.slice(-60)) {
    const canonical = normalizeLabel(line);
    if (!canonical) continue;
    if (usableAnchors.length === 0 || usableAnchors.some((anchor) => canonical.includes(anchor))) {
      selected.push(canonical);
    }
  }
  if (selected.length === 0) {
    return lines.slice(-10).map((line) => normalizeLabel(line)).filter(Boolean).join(' | ');
  }
  return selected.join(' | ');
}

function fingerprintFromBlock(block, anchors) {
  return fingerprintFromLines(block.contextLines, anchors);
}

function updateCurrentSnapshot(next) {
  const prev = currentSnapshot;
  trackLastUserPromptTransition(prev, next);
  trackUsageLimitDismissalTransition(prev, next);
  clearInitialPromptSubmittedFingerprintIfReturned(next);
  if (prev.kind !== next.kind || prev.fingerprint !== next.fingerprint) {
    currentSnapshot = next;
    stateGeneration += 1;
    clearContinueTimer();
    clearMenuPlan();
    if (DEBUG_AUTOMATION) {
      console.error(`[${FLAVOR_LABEL}][state] ${prev.kind}/${prev.source} -> ${next.kind}/${next.source} (#${stateGeneration}) ${next.fingerprint}`);
    }
    if (next.kind !== 'capacity_menu') {
      demandHits = 0;
      lastDemandTs = 0;
    }
    if (next.kind !== 'capacity_continue') {
      autoContinueAttempts = 0;
    }
    recentActionKeys.clear();
    return;
  }
  currentSnapshot = next;
}

function trackUsageLimitDismissalTransition(prev, next) {
  if (prev?.kind === 'usage_limit' && !pendingPromptCommand) {
    pendingPostUsageLimitAdvance = {
      reason: `Usage limit reached on ${currentModel()}`,
      usageLimitModel: String(prev?.usageLimitModel || '').trim(),
      armedAt: Date.now(),
    };
  }

  const capacityKinds = new Set(['capacity_menu', 'capacity_continue', 'capacity_info']);
  if (capacityKinds.has(prev?.kind) && !capacityKinds.has(next?.kind) && !pendingPromptCommand) {
    pendingPostCapacityAdvance = {
      reason: `Capacity limit reached on ${currentModel()}`,
      armedAt: Date.now(),
    };
  }
}

function trackLastUserPromptTransition(prev, next) {
  if (!sentInitialPrompt) return;
  if (pendingPromptCommand) return;
  const prevText = String(prev?.promptInputText || '').trim();
  if (!prevText) return;
  if (prev?.kind !== 'normal' || next?.kind !== 'normal') return;
  const nextText = String(next?.promptInputText || '').trim();
  if (nextText) return;
  if (!next?.chatPromptActive) return;
  if (prevText.startsWith('/')) return;
  if (prevText === lastUserPrompt) return;
  lastUserPrompt = prevText;
  if (DEBUG_AUTOMATION) {
    console.error(`[${FLAVOR_LABEL}][prompt] captured lastUserPrompt (${prevText.length} chars)`);
  }
}

function clearInitialPromptSubmittedFingerprintIfReturned(next) {
  if (!initialPromptSubmittedFingerprint) return;
  const promptFingerprint = String(next?.promptFingerprint || next?.fingerprint || '').trim();
  if (next?.kind !== 'normal' || !next?.chatPromptActive || (promptFingerprint && promptFingerprint !== initialPromptSubmittedFingerprint)) {
    initialPromptSubmittedFingerprint = '';
  }
}

class VirtualScreen {
  constructor(maxRows, maxCols) {
    this.maxRows = Math.max(40, maxRows || 400);
    this.maxCols = Math.max(80, maxCols || 240);
    this.reset();
  }

  reset() {
    this.lines = [[]];
    this.row = 0;
    this.col = 0;
    this.savedRow = 0;
    this.savedCol = 0;
    this.carry = '';
  }

  feed(chunk) {
    const input = this.carry + String(chunk || '');
    this.carry = '';

    for (let i = 0; i < input.length; i += 1) {
      const ch = input[i];
      if (ch === '\u001B') {
        const consumed = this.handleEscape(input, i);
        if (consumed == null) {
          this.carry = input.slice(i);
          break;
        }
        i += consumed - 1;
        continue;
      }

      if (ch === '\r') {
        this.col = 0;
        continue;
      }
      if (ch === '\n') {
        this.row += 1;
        this.ensureRow(this.row);
        this.trimOverflow();
        continue;
      }
      if (ch === '\b') {
        this.col = Math.max(0, this.col - 1);
        continue;
      }
      if (ch === '\t') {
        const spaces = 4 - (this.col % 4 || 0);
        for (let s = 0; s < spaces; s += 1) this.writeChar(' ');
        continue;
      }
      if (ch < ' ' || ch === '\u007F') continue;

      this.writeChar(ch);
    }
  }

  handleEscape(text, start) {
    if (start + 1 >= text.length) return null;
    const next = text[start + 1];

    if (next === '[') return this.handleCsi(text, start);
    if (next === ']') return this.skipTerminatedEscape(text, start, 2);
    if (next === 'P' || next === '^' || next === '_') return this.skipTerminatedEscape(text, start, 2);
    if (next === '7') {
      this.savedRow = this.row;
      this.savedCol = this.col;
      return 2;
    }
    if (next === '8') {
      this.row = this.savedRow;
      this.col = this.savedCol;
      this.ensureRow(this.row);
      return 2;
    }

    return 2;
  }

  skipTerminatedEscape(text, start, prefixLength) {
    for (let i = start + prefixLength; i < text.length; i += 1) {
      if (text[i] === '\u0007') return i - start + 1;
      if (text[i] === '\u001B' && text[i + 1] === '\\') return i - start + 2;
    }
    return null;
  }

  handleCsi(text, start) {
    let end = start + 2;
    while (end < text.length) {
      const code = text.charCodeAt(end);
      if (code >= 0x40 && code <= 0x7E) break;
      end += 1;
    }
    if (end >= text.length) return null;

    const final = text[end];
    const paramsRaw = text.slice(start + 2, end);
    this.applyCsi(final, paramsRaw);
    return end - start + 1;
  }

  applyCsi(final, paramsRaw) {
    const privateMode = paramsRaw.startsWith('?');
    const clean = privateMode ? paramsRaw.slice(1) : paramsRaw;
    const parts = clean.length === 0
      ? []
      : clean.split(';').map((part) => {
          const value = Number(part);
          return Number.isFinite(value) ? value : undefined;
        });
    const p = (index, fallback = 1) => {
      const value = parts[index];
      return Number.isFinite(value) ? value : fallback;
    };

    switch (final) {
      case 'A':
        this.row = Math.max(0, this.row - p(0));
        break;
      case 'B':
        this.row += p(0);
        this.ensureRow(this.row);
        this.trimOverflow();
        break;
      case 'C':
        this.col = Math.min(this.maxCols - 1, this.col + p(0));
        break;
      case 'D':
        this.col = Math.max(0, this.col - p(0));
        break;
      case 'E':
        this.row += p(0);
        this.col = 0;
        this.ensureRow(this.row);
        this.trimOverflow();
        break;
      case 'F':
        this.row = Math.max(0, this.row - p(0));
        this.col = 0;
        break;
      case 'G':
        this.col = Math.max(0, Math.min(this.maxCols - 1, p(0) - 1));
        break;
      case 'H':
      case 'f':
        this.row = Math.max(0, p(0) - 1);
        this.col = Math.max(0, Math.min(this.maxCols - 1, p(1, 1) - 1));
        this.ensureRow(this.row);
        this.trimOverflow();
        break;
      case 'J':
        this.eraseScreen(p(0, 0));
        break;
      case 'K':
        this.eraseLine(p(0, 0));
        break;
      case 'P':
        this.deleteChars(p(0));
        break;
      case 'X':
        this.eraseChars(p(0));
        break;
      case '@':
        this.insertBlankChars(p(0));
        break;
      case 's':
        this.savedRow = this.row;
        this.savedCol = this.col;
        break;
      case 'u':
        this.row = this.savedRow;
        this.col = this.savedCol;
        this.ensureRow(this.row);
        break;
      case 'h':
      case 'l':
        if (privateMode && /^(?:1047|1048|1049)$/.test(clean)) {
          this.lines = [[]];
          this.row = 0;
          this.col = 0;
        }
        break;
      default:
        break;
    }
  }

  writeChar(ch) {
    if (this.col >= this.maxCols) return;
    this.ensureRow(this.row);
    const line = this.lines[this.row];
    while (line.length < this.col) line.push(' ');
    line[this.col] = ch;
    this.col += 1;
  }

  ensureRow(row) {
    while (this.lines.length <= row) this.lines.push([]);
  }

  trimOverflow() {
    if (this.lines.length <= this.maxRows) return;
    const overflow = this.lines.length - this.maxRows;
    this.lines.splice(0, overflow);
    this.row = Math.max(0, this.row - overflow);
    this.savedRow = Math.max(0, this.savedRow - overflow);
  }

  eraseLine(mode) {
    this.ensureRow(this.row);
    const line = this.lines[this.row];
    if (mode === 2) {
      this.lines[this.row] = [];
      return;
    }
    if (mode === 1) {
      for (let i = 0; i <= this.col && i < line.length; i += 1) line[i] = ' ';
      return;
    }
    line.length = Math.min(line.length, this.col);
  }

  eraseScreen(mode) {
    if (mode === 2) {
      this.lines = [[]];
      this.row = 0;
      this.col = 0;
      return;
    }

    this.ensureRow(this.row);
    if (mode === 1) {
      for (let r = 0; r < this.row; r += 1) this.lines[r] = [];
      const line = this.lines[this.row];
      for (let i = 0; i <= this.col && i < line.length; i += 1) line[i] = ' ';
      return;
    }

    this.eraseLine(0);
    for (let r = this.row + 1; r < this.lines.length; r += 1) this.lines[r] = [];
  }

  deleteChars(count) {
    this.ensureRow(this.row);
    const line = this.lines[this.row];
    line.splice(this.col, Math.max(1, count));
  }

  eraseChars(count) {
    this.ensureRow(this.row);
    const line = this.lines[this.row];
    for (let i = 0; i < Math.max(1, count); i += 1) {
      const index = this.col + i;
      if (index >= line.length) break;
      line[index] = ' ';
    }
  }

  insertBlankChars(count) {
    this.ensureRow(this.row);
    const line = this.lines[this.row];
    line.splice(this.col, 0, ...Array.from({ length: Math.max(1, count) }, () => ' '));
    if (line.length > this.maxCols) line.length = this.maxCols;
  }

  renderText(maxLines = 120) {
    const slice = this.lines.slice(-Math.max(20, maxLines));
    const rendered = slice
      .map((line) => line.join('').replace(/\s+$/g, ''))
      .filter((line, index, arr) => !(line === '' && index === 0 && arr.length > 1));
    return rendered.join('\n');
  }
}

function maybeAutomate(runId, snapshot) {
  if (!isAutomationActive()) {
    clearContinueTimer();
    clearPromptCommandTimer();
    clearInitialPromptTimer();
    clearStaticRecheckTimer();
    clearMenuPlan();
    return;
  }

  if (isTransitioningPlannedAction(plannedAction?.kind)) {
    clearContinueTimer();
    clearPromptCommandTimer();
    clearInitialPromptTimer();
    clearStaticRecheckTimer();
    clearMenuPlan();
    return;
  }

  const responders = [
    handleTrustFolderSnapshot,
    handlePermissionSnapshot,
    handleAuthRestartRequiredSnapshot,
    handlePendingPromptCommand,
    handleModelManageRoutingSnapshot,
    handleModelManageModelsSnapshot,
    handlePostUsageLimitAdvance,
    handlePostCapacityAdvance,
    handleUsageLimitSnapshot,
    handleCapacityMenuSnapshot,
    handleCapacityContinueSnapshot,
    handleYesNoSnapshot,
    handleStartupCommandRequeue,
    handleInitialPrompt,
    handleAlwaysPromptSnapshot,
  ];

  for (const responder of responders) {
    if (responder(runId, snapshot)) {
      if (!staticRecheckTimer) scheduleStaticRecheck();
      return;
    }
  }

  clearContinueTimer();
  clearPromptCommandTimer();
  clearMenuPlan();
  scheduleStaticRecheck();
}

function handleInitialPrompt(runId, snapshot) {
  if (!GEMINI_INITIAL_PROMPT || sentInitialPrompt) {
    clearInitialPromptTimer();
    initialPromptPendingSince = 0;
    return false;
  }
  if (pendingPromptCommand) {
    scheduleInitialPromptRetry(runId, `waiting for ${pendingPromptCommand.label || pendingPromptCommand.kind || 'pending command'}`);
    return true;
  }
  if (startupStatsBlockedReason && startupStatsBlocksInitialPrompt) {
    clearInitialPromptTimer();
    initialPromptPendingSince = 0;
    return false;
  }
  if (authHandoffInProgress || authRestartTelemetryPending || suppressInitialPromptForAuthRestart) {
    clearInitialPromptTimer();
    initialPromptPendingSince = 0;
    return false;
  }
  if (snapshot.kind !== 'normal') return false;

  const promptInputText = String(snapshot?.promptInputText || '').trim();
  if (promptInputText) {
    if (isLikelyAutomationPromptInput(promptInputText)) {
      return queueStartupPromptInputClear('stale automated prompt input before initial prompt');
    }
    scheduleInitialPromptRetry(runId, 'waiting for prompt field to clear');
    return true;
  }

  if (initialPromptPendingSince === 0) {
    initialPromptPendingSince = Date.now();
  }

  if (shouldDelayInitialPromptForStartupStats()) {
    scheduleInitialPromptRetry(runId, 'awaiting startup session stats');
    return true;
  }

  if (authWaitSince > 0) {
    scheduleInitialPromptRetry(runId, 'waiting for auth');
    return true;
  }

  const quietForMs = Date.now() - lastTerminalDataAt;
  const waitedForMs = Date.now() - initialPromptPendingSince;
  const canSendWithoutVisiblePrompt = quietForMs >= INITIAL_PROMPT_SETTLE_MS || waitedForMs >= INITIAL_PROMPT_MAX_WAIT_MS;

  if (!snapshot.chatPromptActive && !hasInitialPromptReadySurface(snapshot) && waitedForMs < INITIAL_PROMPT_MAX_WAIT_MS) {
    scheduleInitialPromptRetry(runId, 'awaiting prompt surface');
    return true;
  }

  if (!snapshot.chatPromptActive && !canSendWithoutVisiblePrompt) {
    scheduleInitialPromptRetry(runId, 'awaiting prompt field');
    return true;
  }

  const sendReason = snapshot.chatPromptActive
    ? 'visible prompt field'
    : quietForMs >= INITIAL_PROMPT_SETTLE_MS
      ? `settled normal screen (${quietForMs}ms quiet)`
      : `prompt timeout (${waitedForMs}ms)`;

  return sendInitialPrompt(runId, sendReason, snapshot);
}

function hasInitialPromptReadySurface(snapshot = currentSnapshot) {
  if (snapshot?.chatPromptActive) return true;

  const screenText = [
    currentScreenTerminalText(),
    currentVisibleTerminalText(),
    normalizedTail.slice(-2000),
  ]
    .join('\n')
    .trim();
  if (!screenText) return false;

  return /type\s+your\s+message/i.test(screenText)
    || /\?\s*for\s+shortcuts/i.test(screenText)
    || /workspace[\s\S]{0,160}\/model/i.test(screenText)
    || />\s*$/.test(screenText);
}

function handleAlwaysPromptSnapshot(runId, snapshot) {
  if (!shouldAutoContinuePrompt(snapshot)) return false;
  const command = selectedAutoContinueCommand(snapshot);

  return schedulePromptCommand(runId, snapshot, {
    kind: 'continue',
    text: command.text,
    reason: command.reason,
    label: command.label,
    promptFingerprint: snapshot.promptFingerprint,
  });
}

function handleYesNoSnapshot(runId, snapshot) {
  if (!yoloEnabledForSession || snapshot.kind !== 'normal') return false;
  const tail = normalizedTail.slice(-120).toLowerCase();
  if (tail.includes('[y/n]') || tail.includes('(y/n)')) {
    if (tail.trim().endsWith('?') || tail.trim().endsWith(':') || tail.match(/[y\/n]\s*$/i)) {
      console.error(`\n[${FLAVOR_LABEL}] YOLO: Auto-approving y/n prompt.\n`);
      sendChoice('y', 'yolo-auto-approve', runId);
      return true;
    }
  }
  return false;
}

function handleStartupCommandRequeue(runId, snapshot) {
  if (!shouldRequeueStartupCommand(snapshot)) return false;

  const nextStartupCommand = buildNextStartupCommand();
  if (!nextStartupCommand) return false;

  if (hasPendingSubmitEnter()) {
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  const promptInputText = promptInputTextFromSnapshot(snapshot);
  if (promptInputText) {
    if (isLikelyAutomationPromptInput(promptInputText)) {
      console.error(`\n[${FLAVOR_LABEL}] Startup sequence: clearing stale prompt input before requeueing ${nextStartupCommand.label || nextStartupCommand.text}.\n`);
      return queueStartupPromptInputClear('stale automated prompt input before startup requeue', nextStartupCommand);
    }
    return false;
  }

  pendingPromptCommand = nextStartupCommand;
  console.error(`\n[${FLAVOR_LABEL}] Startup sequence: requeued (${pendingPromptCommand.label || pendingPromptCommand.text}) after prompt recovery.\n`);
  handlePendingPromptCommand(runId, snapshot);
  return true;
}

function isLikelyAutomationPromptInput(text) {
  const normalized = String(text || '').trim();
  if (!normalized) return false;

  return automationPromptCommands().some((command) => normalized === command || normalized.startsWith(command));
}

function promptInputTextFromSnapshot(snapshot) {
  return String(snapshot?.promptInputText || '').trim();
}

function queueStartupPromptInputClear(reason = 'startup prompt input clear', resumeCommand = null) {
  if (!activePty) return false;

  clearPromptCommandTimer();
  clearInitialPromptTimer();
  clearPendingPromptCommandNudgeTimer();
  sendStartupPromptInputClearSequence(reason);
  pendingPromptCommand = {
    kind: 'startup-input-clear-finalize',
    reason,
    resumeCommand,
    createdAt: Date.now(),
    clearSentAt: Date.now(),
    clearAttempts: 1,
    hardClearSentAt: 0,
  };
  scheduleStaticRecheck(QUICK_RECHECK_MS);
  return true;
}

function sendStartupPromptInputClearSequence(reason = 'startup prompt input clear', options = {}) {
  const hard = options.hard === true;
  return sendRaw(hard ? '\x03' : '\x1B\x15', hard ? `${reason}:interrupt-clear` : reason);
}

function automationPromptCommands() {
  return [
    CONTINUE_COMMAND,
    CONTINUE_FALLBACK_COMMAND,
    STARTUP_CLEAR_COMMAND,
    STARTUP_STATS_COMMAND,
    STATS_SESSION_FALLBACK_COMMAND,
    STARTUP_MODEL_COMMAND,
    MODEL_MANAGE_COMMAND,
    AUTH_COMMAND,
  ]
    .map((value) => String(value || '').trim())
    .filter(Boolean);
}

function isAutomationPromptInputLine(text) {
  const line = String(text || '').trim();
  if (!line) return false;
  return automationPromptCommands().some((command) => line === command || line.startsWith(`${command} `));
}

function automationPromptInputCommandLines(text) {
  return String(text || '')
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean)
    .filter(isAutomationPromptInputLine);
}

function retryPendingStartupPromptCommandSubmitIfStuck(runId, command, snapshot, options = {}) {
  if (!command || runId !== activeRunId || !activePty || !isAutomationActive()) return false;

  const commandText = String(command.text || '').trim();
  if (!commandText) return false;

  const promptInputText = promptInputTextFromSnapshot(snapshot) || visibleSubmittedPromptInputText(commandText);
  const commandLines = automationPromptInputCommandLines(promptInputText);
  const containsCurrentCommandLine = commandLines.some((line) => promptInputMatchesSubmittedPrompt(line, commandText));

  if (commandLines.length > 1 && containsCurrentCommandLine) {
    const resumeCommand = options.stackedResumeCommand || null;
    console.error(`\n[${FLAVOR_LABEL}] Startup prompt input contains stacked automated commands; clearing before retrying ${command.label || commandText}.\n`);
    return queueStartupPromptInputClear(
      options.stackedClearReason || `stacked startup automated commands before ${command.label || commandText}`,
      resumeCommand
    );
  }

  if (!promptInputMatchesSubmittedPrompt(promptInputText, commandText)) return false;

  const now = Date.now();
  const retrySettlesAt = Number(command.submitRetrySettlesAt || 0);
  if (Number.isFinite(retrySettlesAt) && retrySettlesAt > now) {
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  const maxAttempts = Math.max(1, INITIAL_PROMPT_SUBMIT_RETRY_MAX);
  const attempts = Number(command.submitRetryAttempts || 0);
  if (attempts < maxAttempts) {
    command.submitRetryAttempts = attempts + 1;
    command.submitRetrySettlesAt = now + INITIAL_PROMPT_SUBMIT_CONFIRM_MS + PROMPT_SUBMIT_SETTLE_MS;
    console.error(`\n[${FLAVOR_LABEL}] ${command.label || commandText} is still in the input field; retrying Enter (${command.submitRetryAttempts}/${maxAttempts}).\n`);
    sendStartupPromptCommandSubmitRetry(runId, command.submitRetryAttempts, command.label || commandText);
    scheduleStaticRecheck(INITIAL_PROMPT_SUBMIT_CONFIRM_MS);
    return true;
  }

  if (typeof options.onExhausted === 'function') {
    return options.onExhausted({
      commandText,
      maxAttempts,
      promptInputText,
    }) === true;
  }

  const resumeCommand = options.exhaustedResumeCommand || null;
  console.error(`\n[${FLAVOR_LABEL}] ${command.label || commandText} stayed in the input field after ${maxAttempts} Enter retries; clearing it before continuing.\n`);
  return queueStartupPromptInputClear(
    options.exhaustedClearReason || `stuck startup slash command ${command.label || commandText}`,
    resumeCommand
  );
}

function sendStartupPromptCommandSubmitRetry(runId, attempt, label = 'startup command') {
  if (runId !== activeRunId || !activePty || !isAutomationActive()) return false;
  try {
    if (attempt >= 2) {
      activePty.write('\x1B');
    }
    activePty.write('\r');
    return true;
  } catch (error) {
    console.error(`[warn] Failed to retry ${label} Enter: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

const PERMISSION_ACTION_TTL_MS = 4000;
function handlePermissionSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'permission') return false;
  if (snapshot.chatPromptActive) return true;
  clearContinueTimer();
  clearPromptCommandTimer();
  if (!AUTO_ALLOW_SESSION_PERMISSIONS) return true;

  const dedupeKey = `permission:${snapshot.fingerprint}:${snapshot.targetOptionText}`;
  if (actionSeenRecently(dedupeKey, PERMISSION_ACTION_TTL_MS)) return true;
  rememberAction(dedupeKey);

  return runMenuPlanForOption(runId, snapshot, snapshot.targetOption, 'allow-for-this-session');
}

function handleTrustFolderSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'trust_folder') return false;
  clearContinueTimer();
  clearPromptCommandTimer();
  if (!AUTO_ALLOW_SESSION_PERMISSIONS) return true;

  return runMenuPlanForOption(runId, snapshot, snapshot.targetOption, 'trust-folder');
}

function handleAuthRestartRequiredSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'auth_restart_required') return false;
  clearContinueTimer();
  clearPromptCommandTimer();
  clearInitialPromptTimer();
  clearMenuPlan();

  authHandoffInProgress = false;
  authRestartTelemetryPending = true;
  suppressInitialPromptForAuthRestart = true;
  sentInitialPrompt = true;
  continueLoopArmed = false;

  if (pendingPromptCommand?.kind === 'auth-restart-finalize') {
    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    if (snapshot.chatPromptActive && waitedForMs >= PROMPT_COMMAND_SETTLE_MS) {
      console.error(`\n[${FLAVOR_LABEL}] Account change telemetry: running ${STARTUP_STATS_COMMAND} -> ${STARTUP_MODEL_COMMAND} without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
      modelIndex = 0;
      avoidProModelsForSession = false;
      pendingPromptCommand = buildPostAuthTelemetryCommand();
      if (!pendingPromptCommand) {
        authRestartTelemetryPending = false;
        return false;
      }
      recheckVisiblePrompt('post-auth telemetry');
      return true;
    }
    if (waitedForMs >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      console.error(`\n[${FLAVOR_LABEL}] Account change restart did not settle in time — relaunching Gemini CLI without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
      requestLauncherAction('restart');
    }
    return true;
  }

  console.error(`\n[${FLAVOR_LABEL}] Account change detected: authentication succeeded; restarting Gemini CLI without startup /clear.\n`);
  sendRaw('R', 'auth-restart');
  pendingPromptCommand = {
    kind: 'auth-restart-finalize',
    createdAt: Date.now(),
  };
  scheduleStaticRecheck(QUICK_RECHECK_MS);
  return true;
}

function handlePendingPromptCommand(runId, snapshot) {
  if (!pendingPromptCommand) return false;
  if (isPromptCommandSubmitSettling(pendingPromptCommand)) {
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  if (confirmVisibleModelForPendingModelManageSwitch(pendingPromptCommand)) {
    return false;
  }

  if (pendingPromptCommand.kind === 'startup-input-clear-finalize') {
    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    const promptInputText = String(snapshot?.promptInputText || '').trim();
    const settleMs = Math.max(40, PROMPT_COMMAND_SETTLE_MS);

    if (waitedForMs < settleMs) return true;

    if (promptInputText && waitedForMs < MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      if (waitedForMs - (pendingPromptCommand.clearSentAt || 0) >= settleMs) {
        const clearAttempts = Number(pendingPromptCommand.clearAttempts || 0);
        const useHardClear = clearAttempts >= 3 && !pendingPromptCommand.hardClearSentAt;
        sendStartupPromptInputClearSequence('startup-input-clear-retry', { hard: useHardClear });
        pendingPromptCommand.clearSentAt = Date.now();
        pendingPromptCommand.clearAttempts = clearAttempts + 1;
        if (useHardClear) pendingPromptCommand.hardClearSentAt = Date.now();
      }
      return true;
    }

    if (promptInputText) {
      setStartupStatsBlocked('startup prompt input could not be cleared before initial prompt injection');
      return true;
    }

    const resumeCommand = pendingPromptCommand.resumeCommand || null;
    pendingPromptCommand = resumeCommand;
    if (resumeCommand) {
      recheckVisiblePrompt('startup command after prompt input clear');
      return true;
    }
    return false;
  }
  if (pendingPromptCommand.kind === 'auth-restart-finalize') {
    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    if (snapshot.kind === 'auth_restart_required') return true;

    if (snapshot.kind === 'normal' && (snapshot.chatPromptActive || waitedForMs >= PROMPT_COMMAND_SETTLE_MS)) {
      console.error(`\n[${FLAVOR_LABEL}] Account change telemetry: running ${STARTUP_STATS_COMMAND} -> ${STARTUP_MODEL_COMMAND} without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
      modelIndex = 0;
      avoidProModelsForSession = false;
      pendingPromptCommand = buildPostAuthTelemetryCommand();
      if (!pendingPromptCommand) {
        authRestartTelemetryPending = false;
        return false;
      }
      recheckVisiblePrompt('post-auth telemetry');
      return true;
    }

    if (waitedForMs >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      console.error(`\n[${FLAVOR_LABEL}] Account change restart did not settle in time — relaunching Gemini CLI without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
      requestLauncherAction('restart');
      return true;
    }

    return true;
  }
  if (pendingPromptCommand.kind === 'startup-clear-finalize') {
	    const settled = hasStartupClearSettled(snapshot, {
	      screenText: currentScreenTerminalText(),
	      visibleText: currentVisibleTerminalText(),
	      waitedForMs: Date.now() - (pendingPromptCommand.createdAt || 0),
	      submitSettlesAt: pendingPromptCommand.submitSettlesAt,
	      submittedAt: pendingPromptCommand.submittedAt,
	    });
    if (settled) {
      startupClearCompleted = true;
      console.error(`\n[${FLAVOR_LABEL}] Startup clear: completed (${pendingPromptCommand.detail || pendingPromptCommand.label || STARTUP_CLEAR_COMMAND})\n`);
      pendingPromptCommand = delayPromptCommandAfterSlashSubmit(buildNextStartupCommand());
      if (!pendingPromptCommand) return false;
      recheckVisiblePrompt('startup stats after clear');
      return true;
    }
    if (Date.now() - (pendingPromptCommand.createdAt || 0) >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      setStartupStatsBlocked(`startup ${STARTUP_CLEAR_COMMAND} did not return to the chat prompt in time`);
      return true;
    }
    return true;
  }
  if (pendingPromptCommand.kind === 'startup-stats-finalize') {
    if (retryPendingStartupPromptCommandSubmitIfStuck(runId, pendingPromptCommand, snapshot, {
      stackedResumeCommand: buildStartupStatsCommand(),
      stackedClearReason: 'stacked startup slash commands before session stats telemetry',
      exhaustedResumeCommand: buildStartupModelCommand(),
      exhaustedClearReason: 'startup stats command stayed in prompt input before model telemetry',
    })) {
      return true;
    }

	    const settled = hasStartupStatsCaptureSettled(snapshot, {
	      startupStatsObserved,
	      screenText: currentScreenTerminalText(),
	      visibleText: currentVisibleTerminalText(),
	      waitedForMs: Date.now() - (pendingPromptCommand.createdAt || 0),
	      submitSettlesAt: pendingPromptCommand.submitSettlesAt,
	    });
    if (settled) {
      const captureSummary = describeStartupStatsCapture(startupStatsSnapshot);
      console.error(`\n[${FLAVOR_LABEL}] Startup session stats: captured (${captureSummary})\n`);
      startupModelCapacityObserved = false;
      startupModelCapacitySnapshot = null;
      pendingPromptCommand = delayPromptCommandAfterSlashSubmit(buildStartupModelCommand());
      if (!pendingPromptCommand) return false;
      recheckVisiblePrompt('startup model capacity after stats');
      return true;
    }
    if (Date.now() - (pendingPromptCommand.createdAt || 0) >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      if (!startupStatsObserved) {
        const fallbackCommand = buildStartupStatsFallbackCommand(pendingPromptCommand);
        if (fallbackCommand) {
          console.error(`\n[${FLAVOR_LABEL}] startup ${pendingPromptCommand.text || STATS_SESSION_COMMAND} output was not detected in time — retrying with ${fallbackCommand.text}.\n`);
          pendingPromptCommand = fallbackCommand;
          recheckVisiblePrompt('startup stats fallback');
          return true;
        }
      }

      const reason = startupStatsObserved
        ? `startup ${STARTUP_STATS_COMMAND} did not return to the chat prompt in time`
        : `startup ${STARTUP_STATS_COMMAND} output was not detected in time`;
      setStartupStatsBlocked(reason, { blocksInitialPrompt: false });
      startupModelCapacityObserved = false;
      startupModelCapacitySnapshot = null;
      const nextCommand = buildStartupModelCommand();
      if (!nextCommand) return false;
      return queueStartupPromptInputClear('startup stats command timed out before model telemetry', nextCommand);
    }
    return true;
  }
  if (pendingPromptCommand.kind === 'startup-model-finalize') {
    if (retryPendingStartupPromptCommandSubmitIfStuck(runId, pendingPromptCommand, snapshot, {
      stackedResumeCommand: buildStartupModelCommand(),
      stackedClearReason: 'stacked startup slash commands before model telemetry',
      exhaustedClearReason: 'startup model command stayed in prompt input before initial prompt',
    })) {
      return true;
    }

    if (MODEL_AUTO && pendingPromptCommand.autoModelSelectionAttempted && snapshot.kind === 'normal') {
      const selectedLabel = pendingPromptCommand.autoModelSelectionTargetLabel || GEMINI_AUTO_MODEL || 'auto';
      startupModelCapacityObserved = true;
      startupModelCapacitySnapshot = startupModelCapacitySnapshot || {
        currentModel: selectedLabel,
        rows: [],
        rawLines: [],
      };
      console.error(`\n[${FLAVOR_LABEL}] Startup auto model: selected ${selectedLabel}; continuing startup.\n`);
      pendingPromptCommand = null;
      return false;
    }

    if (MODEL_AUTO && !pendingPromptCommand.autoModelSelectionCompleted) {
      const autoModelOption = resolveStartupAutoModelOption(snapshot);
      if (autoModelOption) {
        const selectedLabel = autoModelOption.label || autoModelOption.canonical || GEMINI_AUTO_MODEL || 'auto';
        pendingPromptCommand.autoModelSelectionAttempted = true;
        pendingPromptCommand.autoModelSelectionTargetLabel = selectedLabel;

        if (!pendingPromptCommand.autoModelSelectionLogged) {
          console.error(`\n[${FLAVOR_LABEL}] Startup auto model: selecting ${selectedLabel} from ${STARTUP_MODEL_COMMAND}.\n`);
          pendingPromptCommand.autoModelSelectionLogged = true;
        }

        return runMenuPlanForOption(runId, snapshot, autoModelOption, 'startup-auto-model');
      }
    }

    captureStartupModelCapacityObservation();
    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    if (startupModelCapacityObserved && !pendingPromptCommand.closeSentAt) {
      const captureSummary = describeStartupModelCapacityCapture(startupModelCapacitySnapshot);
      console.error(`\n[${FLAVOR_LABEL}] Startup model capacity: captured (${captureSummary})\n`);
      sendRaw('\x1B', 'startup-model-close');
      pendingPromptCommand.closeSentAt = Date.now();
      recheckVisiblePrompt('startup model close');
      return true;
    }

    if (pendingPromptCommand.closeSentAt) {
      const closed = hasStartupModelCapacityClosed(snapshot, {
        screenText: currentScreenTerminalText(),
        visibleText: currentVisibleTerminalText(),
        waitedForMs: Date.now() - pendingPromptCommand.closeSentAt,
      });
      if (closed) {
        if (maybeAdvanceFromStartupModelCapacityBeforePrompt(snapshot)) {
          return true;
        }
        pendingPromptCommand = null;
        if (authRestartTelemetryPending) {
          authRestartTelemetryPending = false;
          suppressInitialPromptForAuthRestart = false;
          sentInitialPrompt = true;
          continueLoopArmed = false;
          console.error(`\n[${FLAVOR_LABEL}] Account change telemetry: captured refreshed /stats and /model capacity; startup /clear was skipped.\n`);
        }
        return false;
      }
      if (Date.now() - pendingPromptCommand.closeSentAt >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
        setStartupStatsBlocked(`startup ${STARTUP_MODEL_COMMAND} did not return to the chat prompt in time`, { blocksInitialPrompt: false });
        return true;
      }
      return true;
    }

    if (waitedForMs >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      setStartupStatsBlocked(`startup ${STARTUP_MODEL_COMMAND} output was not detected in time`, { blocksInitialPrompt: false });
      return queueStartupPromptInputClear('startup model command timed out before initial prompt');
    }
    return true;
  }
  if (pendingPromptCommand.kind === 'usage-limit-stop-finalize') {
    clearContinueTimer();
    clearPromptCommandTimer();

    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    const reason = pendingPromptCommand.reason || `Usage limit reached on ${currentModel()}`;

    if (snapshot.kind === 'usage_limit' && snapshot.usageLimitPromptActive && snapshot.chatPromptActive) {
      if (!pendingPromptCommand.stopOptionSeenAt) {
        console.error(`\n[${FLAVOR_LABEL}] ${reason} — selecting Stop before switching models.\n`);
      }
      pendingPromptCommand = null;
      clearMenuPlan();
      requestModelAdvanceOrFinish(reason, {
        allowBackwardVisibleReconcile: false,
        retryInitialPromptAfterSwitch: shouldRetryInitialPromptAfterUsageLimit(),
        snapshot,
      });
      return true;
    }

    if (snapshot.kind === 'usage_limit') {
      if (snapshot.stopOption) {
        if (!pendingPromptCommand.stopOptionSeenAt) {
          pendingPromptCommand.stopOptionSeenAt = Date.now();
          console.error(`\n[${FLAVOR_LABEL}] ${reason} — selecting Stop before switching models.\n`);
        }
        return runMenuPlanForOption(runId, snapshot, snapshot.stopOption, 'dismiss-usage-limit');
      }

      if (waitedForMs >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
        pendingPromptCommand = null;
        clearMenuPlan();
        requestModelAdvanceOrFinish(reason, {
          forceRelaunch: true,
          forceRelaunchDetail: 'usage limit screen has no Stop option',
          allowBackwardVisibleReconcile: false,
          retryInitialPromptAfterSwitch: shouldRetryInitialPromptAfterUsageLimit(),
          snapshot,
        });
      }
      return true;
    }

    if (snapshot.kind === 'normal' && (snapshot.chatPromptActive || waitedForMs >= PROMPT_COMMAND_SETTLE_MS)) {
      pendingPromptCommand = null;
      clearMenuPlan();
      requestModelAdvanceOrFinish(reason, {
        allowBackwardVisibleReconcile: false,
        retryInitialPromptAfterSwitch: shouldRetryInitialPromptAfterUsageLimit(),
        snapshot,
      });
      return true;
    }

    if (waitedForMs >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      pendingPromptCommand = null;
      clearMenuPlan();
      requestModelAdvanceOrFinish(reason, {
        forceRelaunch: true,
        forceRelaunchDetail: 'usage limit Stop did not return to prompt',
        allowBackwardVisibleReconcile: false,
        retryInitialPromptAfterSwitch: shouldRetryInitialPromptAfterUsageLimit(),
        snapshot,
      });
    }
    return true;
  }
  if (adoptPendingModelSwitchTargetForUsageLimit(snapshot)) {
    return false;
  }
  if (pendingPromptCommand.kind === 'model-switch-finalize') {
    const targetModel = pendingPromptCommand.targetModel || '';
    if (retryPendingStartupPromptCommandSubmitIfStuck(runId, pendingPromptCommand, snapshot, {
      stackedResumeCommand: buildDirectModelSwitchCommand(
        pendingPromptCommand.targetIndex,
        pendingPromptCommand.advanceReason || pendingPromptCommand.reason || `model-switch ${pendingPromptCommand.targetModel || 'target model'}`,
        MODELS,
        {
          retryInitialPromptAfterSwitch: pendingPromptCommand.retryInitialPromptAfterSwitch === true,
        }
      ),
      stackedClearReason: 'stacked automated prompt input before model switch confirmation',
      exhaustedClearReason: 'model switch command stayed in prompt input before confirmation',
      onExhausted: ({ maxAttempts }) => relaunchPendingModelManageTarget(
        `direct model switch to ${targetModel || 'target model'} stayed in prompt input after ${maxAttempts} Enter retries`
      ),
    })) {
      return true;
    }

    const resolution = resolveDirectModelSwitchConfirmation(targetModel, {
      screenText: currentScreenTerminalText(),
      visibleText: currentVisibleTerminalText(),
    });
    if (resolution.confirmed) {
      if (Number.isInteger(pendingPromptCommand.targetIndex)) {
        modelIndex = pendingPromptCommand.targetIndex;
      }
      console.error(`\n[${FLAVOR_LABEL}] Model switch confirmed: ${resolution.observedModel || targetModel}.\n`);
      const retryInitialPrompt = pendingPromptCommand.retryInitialPromptAfterSwitch === true;
      pendingPromptCommand = null;
      if (retryInitialPrompt) rearmInitialPromptAfterUsageLimitSwitch(targetModel);
      return false;
    }

    if (Date.now() - (pendingPromptCommand.createdAt || 0) >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      const observedDetail = resolution.observedModel
        ? `; visible model is ${resolution.observedModel}`
        : '; no current model was visible';
      return relaunchPendingModelManageTarget(`direct model switch to ${targetModel || 'target model'} was not confirmed${observedDetail}`);
    }
    return true;
  }
  if (pendingPromptCommand.kind === 'model-manage-finalize') {
    if (snapshot.kind === 'normal' && snapshot.chatPromptActive) {
      const targetModel = pendingPromptCommand.targetModel || '';
      const resolution = resolveDirectModelSwitchConfirmation(targetModel, {
        screenText: currentScreenTerminalText(),
        visibleText: currentVisibleTerminalText(),
      });
      if (!resolution.confirmed) {
        if (Date.now() - (pendingPromptCommand.createdAt || 0) >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
          const observedDetail = resolution.observedModel
            ? `; visible model is ${resolution.observedModel}`
            : '; no current model was visible';
          return relaunchPendingModelManageTarget(`model manage switch to ${targetModel || 'target model'} was not confirmed${observedDetail}`);
        }
        return true;
      }
      if (Number.isInteger(pendingPromptCommand.targetIndex)) {
        modelIndex = pendingPromptCommand.targetIndex;
      }
      console.error(`\n[${FLAVOR_LABEL}] Model switch confirmed: ${resolution.observedModel || targetModel}.\n`);
      const retryInitialPrompt = pendingPromptCommand.retryInitialPromptAfterSwitch === true;
      pendingPromptCommand = null;
      if (retryInitialPrompt) rearmInitialPromptAfterUsageLimitSwitch(targetModel);
    }
    return false;
  }

  const pendingRecoveryAction = resolvePendingModelManageRecoveryAction({
    pendingKind: pendingPromptCommand.kind,
    snapshotKind: snapshot.kind,
    chatPromptActive: snapshot.chatPromptActive,
    authWaiting: authWaitSince > 0,
    elapsedMs: Date.now() - (pendingPromptCommand.createdAt || 0),
    timeoutMs: MODEL_MANAGE_FLOW_TIMEOUT_MS,
  });
  if (pendingRecoveryAction === 'direct-switch') {
    return fallbackPendingModelManageFlow(`${pendingPromptCommand.kind} timed out`);
  }
  if (pendingRecoveryAction === 'relaunch-target') {
    return relaunchPendingModelManageTarget(`${pendingPromptCommand.kind} timed out`);
  }

  const canSendWithoutVisiblePrompt = canSendPromptCommandWithoutVisiblePrompt(pendingPromptCommand, snapshot);
  if (!snapshot.chatPromptActive && !canSendWithoutVisiblePrompt) {
    if (pendingPromptCommand.kind === 'model-switch') {
      const cancelOutcome = nudgeSpinnerForPendingModelSwitch();
      if (cancelOutcome === 'sent') {
        scheduleStaticRecheck(QUICK_RECHECK_MS);
        return true;
      }
      if (cancelOutcome === 'exhausted') {
        return relaunchPendingModelManageTarget('model-switch could not cancel Gemini CLI thinking spinner');
      }
    }
    if (pendingPromptCommand.kind !== 'startup-stats' && pendingPromptCommand.kind !== 'stats-session') {
      clearPromptCommandTimer();
    }
    return false;
  }
  if (snapshot.kind !== 'normal' && snapshot.kind !== 'usage_limit') {
    clearPromptCommandTimer();
    return false;
  }

  return schedulePromptCommand(runId, snapshot, pendingPromptCommand);
}

function adoptPendingModelSwitchTargetForUsageLimit(snapshot) {
  if (snapshot?.kind !== 'usage_limit') return false;
  const resolution = resolvePendingModelSwitchTargetForUsageLimit(pendingPromptCommand);
  if (!resolution) return false;

  const switchConfirmation = resolveDirectModelSwitchConfirmation(resolution.targetModel, {
    screenText: currentScreenTerminalText(),
    visibleText: currentVisibleTerminalText(),
  });
  if (switchConfirmation.confirmed) {
    modelIndex = resolution.targetIndex;
    const confirmedModel = switchConfirmation.observedModel || resolution.targetModel || currentModel();
    const retryInitialPrompt = pendingPromptCommand.retryInitialPromptAfterSwitch === true;
    pendingPromptCommand = null;
    console.error(`\n[${FLAVOR_LABEL}] Model switch confirmed: ${confirmedModel}.\n`);
    if (retryInitialPrompt) rearmInitialPromptAfterUsageLimitSwitch(confirmedModel);
    return true;
  }

  if (!usageLimitSnapshotMatchesVisibleModel(snapshot)) return false;
  if (wasUsageLimitSnapshotHandledRecently(snapshot)) return false;

  const pendingKind = String(pendingPromptCommand?.kind || '');
  const adoptionGraceMs = Math.min(2500, MODEL_MANAGE_FLOW_TIMEOUT_MS);
  if (pendingKind === 'model-switch') {
    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    if (waitedForMs < adoptionGraceMs) return false;
  }

  const usageLimitModel = String(snapshot?.usageLimitModel || '').trim();
  if (usageLimitModel && resolution.targetModel) {
    if (!modelIdentifiersMatch(usageLimitModel, resolution.targetModel)) {
      const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
      if (waitedForMs < adoptionGraceMs) return false;
    }
  }
  if (!usageLimitModel) {
    if (pendingKind !== 'model-switch-finalize') return false;
    const waitedForMs = Date.now() - (pendingPromptCommand.createdAt || 0);
    if (waitedForMs < MODEL_MANAGE_FLOW_TIMEOUT_MS) return false;
  }

  modelIndex = resolution.targetIndex;
  snapshot.usageLimitModel = resolution.targetModel || snapshot.usageLimitModel;
  snapshot.ignoreVisibleModelMismatch = true;
  pendingPromptCommand = null;
  console.error(`\n[${FLAVOR_LABEL}] Usage limit appeared while confirming ${resolution.targetModel || currentModel()}; treating that model as active for fallback.\n`);
  return true;
}

function resolvePendingModelSwitchTargetForUsageLimit(command, models = MODELS) {
  const kind = String(command?.kind || '');
  if (kind !== 'model-switch-finalize' && kind !== 'model-manage-finalize') return null;

  const chain = Array.isArray(models) ? models : [];
  const targetIndex = command.targetIndex;
  if (!Number.isInteger(targetIndex) || targetIndex < 0 || targetIndex >= chain.length) return null;

  const targetModel = command.targetModel || chain[targetIndex] || '';
  return {
    targetIndex,
    targetModel,
  };
}

function confirmVisibleModelForPendingModelManageSwitch(command) {
  const kind = String(command?.kind || '').trim();
  if (
    kind !== 'model-manage-open' &&
    kind !== 'model-manage-route' &&
    kind !== 'model-manage-select'
  ) {
    return false;
  }

  const targetIndex = Number(command?.targetIndex);
  if (!Number.isInteger(targetIndex) || targetIndex < 0 || targetIndex >= MODELS.length) return false;

  const observedModel = extractVisibleCurrentModel(currentScreenTerminalText())
    || extractVisibleCurrentModel(currentVisibleTerminalText());
  const observedIndex = findModelIndexByIdentifier(observedModel, MODELS);
  if (observedIndex < targetIndex) return false;

  modelIndex = observedIndex;
  const confirmedModel = MODELS[observedIndex] || observedModel;
  if (observedIndex !== targetIndex) {
    const skipped = command.targetModel || MODELS[targetIndex] || 'target model';
    const reason = command.advanceReason || command.reason || `Usage limit reached on ${skipped}`;
    console.error(`\n[${FLAVOR_LABEL}] ${reason} — ${skipped} is at 100% usage; selecting ${confirmedModel} instead.\n`);
  }
  console.error(`\n[${FLAVOR_LABEL}] Model switch confirmed: ${observedModel || confirmedModel}.\n`);
  const retryInitialPrompt = command.retryInitialPromptAfterSwitch === true;
  pendingPromptCommand = null;
  clearPromptCommandTimer();
  clearPendingPromptCommandNudgeTimer();
  if (retryInitialPrompt) rearmInitialPromptAfterUsageLimitSwitch(confirmedModel);
  return true;
}

function resolveStartupAutoModelOption(snapshot) {
  if (!MODEL_AUTO) return null;
  const options = Array.isArray(snapshot?.options) ? snapshot.options : [];
  const autoOptions = options.filter(isAutoModelMenuOption);
  if (autoOptions.length === 0) return null;

  const requested = normalizeLabel(GEMINI_AUTO_MODEL);
  if (requested && requested !== 'auto') {
    const requestedOption = autoOptions.find((option) => normalizeLabel(option.canonical) === requested)
      || autoOptions.find((option) => normalizeLabel(option.label || '').includes(requested))
      || autoOptions.find((option) => normalizeLabel(option.canonical).includes(requested));
    if (requestedOption) return requestedOption;
  }

  const preferredFamily = preferredStartupAutoModelFamily();
  if (preferredFamily) {
    const familyOption = autoOptions.find((option) => normalizeLabel(option.canonical).includes(preferredFamily))
      || autoOptions.find((option) => normalizeLabel(option.label || '').includes(preferredFamily));
    if (familyOption) return familyOption;
  }

  return autoOptions[0] || null;
}

function isAutoModelMenuOption(option) {
  const canonical = normalizeLabel(option?.canonical || option?.label || '');
  return /^auto\s*\(\s*gemini\s+(?:3|2\.5)\s*\)/i.test(canonical);
}

function preferredStartupAutoModelFamily() {
  const firstModel = String(MODELS.find((model) => String(model || '').trim()) || currentModel() || '').trim();
  if (/^gemini-3\b/i.test(firstModel)) return 'gemini 3';
  if (/^gemini-2\.5\b/i.test(firstModel)) return 'gemini 2.5';
  return '';
}

function handleModelManageRoutingSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'model_manage_routing') return false;
  if (pendingPromptCommand?.kind !== 'model-manage-route') return false;
  clearContinueTimer();
  clearPromptCommandTimer();

  const manualOption = snapshot.targetOption || snapshot.options.find((option) => option.canonical.startsWith('manual'));
  if (!manualOption) {
    fallbackPendingModelManageFlow('manual routing option missing');
    return true;
  }

  pendingPromptCommand = {
    kind: 'model-manage-select',
    targetIndex: pendingPromptCommand.targetIndex,
    targetModel: pendingPromptCommand.targetModel,
    advanceReason: pendingPromptCommand.advanceReason,
    retryInitialPromptAfterSwitch: pendingPromptCommand.retryInitialPromptAfterSwitch === true,
    createdAt: Date.now(),
  };
  return runMenuPlanForOption(runId, snapshot, manualOption, 'model-manage-manual');
}

function handleModelManageModelsSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'model_manage_models') return false;
  const pendingKind = String(pendingPromptCommand?.kind || '');
  const acceptedKinds = new Set([
    'model-manage-select',
    'model-manage-route',
    'model-switch',
    'model-switch-finalize',
  ]);
  if (!acceptedKinds.has(pendingKind)) return false;
  clearContinueTimer();
  clearPromptCommandTimer();

  const targetResolution = resolveModelManageSelectionTarget(snapshot, pendingPromptCommand);
  const targetOption = targetResolution?.option || null;

  if (!targetOption) {
    if (Date.now() - (pendingPromptCommand.createdAt || 0) >= MODEL_MANAGE_FLOW_TIMEOUT_MS) {
      fallbackPendingModelManageFlow(`target model ${pendingPromptCommand.targetModel || '(unknown)'} not found in /model manage`);
    }
    return true;
  }

  if (targetResolution.targetIndex !== pendingPromptCommand.targetIndex) {
    const skipped = pendingPromptCommand.targetModel || MODELS[pendingPromptCommand.targetIndex] || 'target model';
    const reason = pendingPromptCommand.advanceReason || pendingPromptCommand.reason || `Usage limit reached on ${currentModel()}`;
    console.error(`\n[${FLAVOR_LABEL}] ${reason} — ${skipped} is at 100% usage; selecting ${targetResolution.targetModel} instead.\n`);
  }

  pendingPromptCommand = {
    kind: 'model-manage-finalize',
    targetIndex: targetResolution.targetIndex,
    targetModel: targetResolution.targetModel,
    advanceReason: pendingPromptCommand.advanceReason,
    retryInitialPromptAfterSwitch: pendingPromptCommand.retryInitialPromptAfterSwitch === true,
    createdAt: Date.now(),
  };
  return runMenuPlanForOption(runId, snapshot, targetOption, 'model-manage-select');
}

function resolveModelManageSelectionTarget(snapshot, command) {
  const modelOptions = Array.isArray(snapshot?.modelOptions) ? snapshot.modelOptions : [];
  if (modelOptions.length === 0) return null;

  const capacityRows = Array.isArray(snapshot?.capacityRows) ? snapshot.capacityRows : [];
  const targetIndex = Number(command?.targetIndex);
  const targetModel = command?.targetModel || (Number.isInteger(targetIndex) ? MODELS[targetIndex] : '');
  const directOption = findModelManageOptionForModel(modelOptions, targetModel);

  if (!isModelAtFullCapacity(targetModel, capacityRows) && directOption) {
    return {
      targetIndex,
      targetModel,
      option: directOption,
    };
  }

  const fallbackStart = Number.isInteger(targetIndex) ? targetIndex - 1 : modelIndex;
  const fallbackIndex = findNextEligibleModelIndexInChain(MODELS, fallbackStart, {
    avoidProModels: avoidProModelsForSession,
    avoidFullCapacityModels: true,
    capacityRows,
    requireFallbackDowngrade: true,
    fallbackFromModel: targetModel,
  });

  if (fallbackIndex >= 0) {
    const fallbackModel = MODELS[fallbackIndex];
    const fallbackOption = findModelManageOptionForModel(modelOptions, fallbackModel);
    if (fallbackOption) {
      return {
        targetIndex: fallbackIndex,
        targetModel: fallbackModel,
        option: fallbackOption,
      };
    }
  }

  return directOption
    ? {
      targetIndex,
      targetModel,
      option: directOption,
    }
    : null;
}

function maybeAdvanceFromStartupModelCapacityBeforePrompt(snapshot) {
  if (!GEMINI_INITIAL_PROMPT || sentInitialPrompt) return false;
  if (authHandoffInProgress || authRestartTelemetryPending || suppressInitialPromptForAuthRestart) return false;

  const resolution = resolveStartupModelCapacityFallbackTarget(startupModelCapacitySnapshot);
  if (!resolution) return false;

  const fromModel = resolution.fromModel || currentModel();
  const reason = `Startup model capacity shows ${fromModel} is at 100% usage`;
  pendingPromptCommand = null;
  const result = requestModelAdvanceOrFinish(reason, {
    allowBackwardVisibleReconcile: false,
    avoidFullCapacityModels: true,
    capacityRows: resolution.capacityRows,
    fallbackFromModel: fromModel,
    requireFallbackDowngrade: true,
    retryInitialPromptAfterSwitch: false,
    snapshot,
  });

  return result !== 'transitioning';
}

function resolveStartupModelCapacityFallbackTarget(capacitySnapshot, models = MODELS) {
  const rows = Array.isArray(capacitySnapshot?.rows) ? capacitySnapshot.rows : [];
  if (rows.length === 0) return null;

  const snapshotModel = String(capacitySnapshot?.currentModel || '').trim();
  const fromModel = snapshotModel || currentModel();
  if (!isStartupCurrentModelAtFullCapacity(fromModel, rows)) return null;

  const fromIndex = findModelIndexByIdentifier(fromModel, models);
  if (fromIndex >= 0) modelIndex = fromIndex;

  const targetIndex = findNextEligibleModelIndexInChain(models, fromIndex >= 0 ? fromIndex : modelIndex, {
    avoidProModels: avoidProModelsForSession,
    avoidFullCapacityModels: true,
    capacityRows: rows,
    requireFallbackDowngrade: true,
    fallbackFromModel: fromModel,
  });

  return {
    fromModel,
    fromIndex,
    targetIndex,
    targetModel: targetIndex >= 0 ? models[targetIndex] : '',
    capacityRows: rows,
  };
}

function isStartupCurrentModelAtFullCapacity(model, rows = []) {
  const row = findStartupCapacityRowForCurrentModel(model, rows);
  if (!row) return false;
  return Number(row.usedPercentage) >= 100;
}

function findStartupCapacityRowForCurrentModel(model, rows = []) {
  return findCapacityRowForModel(model, rows)
    || rows.find((row) => capacityRowLabelMatchesModelTier(row?.model, model))
    || null;
}

function capacityRowLabelMatchesModelTier(rowModel, model) {
  const rowLabel = normalizeCapacityModelLabel(rowModel);
  if (!rowLabel) return false;
  return startupCapacityModelTierLabels(model).includes(rowLabel);
}

function normalizeCapacityModelLabel(value) {
  return normalizeLabel(String(value || '').replace(/[-_]+/g, ' '));
}

function startupCapacityModelTierLabels(model) {
  const normalized = normalizeModelIdentifier(model);
  if (!normalized) return [];
  if (/\bflash-lite\b/.test(normalized) || /\blite\b/.test(normalized)) {
    return ['flash lite', 'flashlite', 'lite'];
  }
  if (/\bflash\b/.test(normalized)) return ['flash'];
  if (/\bpro\b/.test(normalized)) return ['pro'];
  return [];
}

function findModelManageOptionForModel(modelOptions, model) {
  const target = String(model || '').trim();
  if (!target) return null;
  return modelOptions.find((option) => modelIdentifiersMatch(option.modelIdentifier || option.canonical, target))
    || modelOptions.find((option) => normalizeLabel(option.canonical).includes(normalizeLabel(target)))
    || null;
}

function handlePostUsageLimitAdvance(runId, snapshot) {
  if (!pendingPostUsageLimitAdvance) return false;
  if (snapshot.kind !== 'normal' || !snapshot.chatPromptActive) return false;
  if (pendingPromptCommand) return false;
  if (authHandoffInProgress || authRestartTelemetryPending) {
    pendingPostUsageLimitAdvance = null;
    return false;
  }
  if (lastExistingUsageLimitHandlerAt > 0 && Date.now() - lastExistingUsageLimitHandlerAt < SAFETY_NET_DEBOUNCE_MS) {
    pendingPostUsageLimitAdvance = null;
    return false;
  }

  const armed = pendingPostUsageLimitAdvance;
  pendingPostUsageLimitAdvance = null;

  if (!automationEnabled && AUTO_DISABLE_ON_USAGE_LIMIT) {
    setAutomationEnabled(true, 'usage_limit_recovery');
  }
  if (!canAutoAdvanceUsageLimitModelChain()) return false;

  if (armed.usageLimitModel) {
    reconcileModelIndexFromUsageLimitModel(armed.usageLimitModel, 'post-usage-limit advance');
  }

  return advanceModelChainOrAuth(armed.reason, snapshot);
}

let lastSafetyNetAdvanceAt = 0;
let lastSafetyNetAdvanceFromModel = '';
function advanceModelChainOrAuth(reason, snapshot) {
  const fromModel = currentModel();
  const now = Date.now();
  if (lastSafetyNetAdvanceFromModel === fromModel && now - lastSafetyNetAdvanceAt < SAFETY_NET_DEBOUNCE_MS) {
    return false;
  }
  lastSafetyNetAdvanceFromModel = fromModel;
  lastSafetyNetAdvanceAt = now;

  const nextIndex = findNextEligibleModelIndex(modelIndex);
  if (nextIndex < 0) {
    console.error(`\n[${FLAVOR_LABEL}] ${reason} — no fallback models in chain.\n`);
    handleModelChainExhausted(reason, { snapshot });
    return true;
  }

  console.error(`\n[${FLAVOR_LABEL}] ${reason} — switching to ${MODELS[nextIndex]} via direct /model command.\n`);
  if (!queueDirectModelSwitchCommand(nextIndex, reason, { retryInitialPromptAfterSwitch: true })) {
    handleModelChainExhausted(reason, { snapshot });
    return true;
  }
  scheduleStaticRecheck(QUICK_RECHECK_MS);
  return true;
}

function handlePostCapacityAdvance(runId, snapshot) {
  if (!pendingPostCapacityAdvance) return false;
  if (snapshot.kind !== 'normal' || !snapshot.chatPromptActive) return false;
  if (pendingPromptCommand) return false;
  if (authHandoffInProgress || authRestartTelemetryPending) {
    pendingPostCapacityAdvance = null;
    return false;
  }
  if (NEVER_SWITCH || !automationEnabled) {
    pendingPostCapacityAdvance = null;
    return false;
  }

  const armed = pendingPostCapacityAdvance;
  pendingPostCapacityAdvance = null;

  return advanceModelChainOrAuth(armed.reason, snapshot);
}

function handleUsageLimitSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'usage_limit') return false;

  const inFlightSwitchKinds = new Set([
    'model-switch',
    'model-switch-finalize',
    'usage-limit-stop-finalize',
    'auth',
    'auth-restart-finalize',
  ]);
  if (pendingPromptCommand && inFlightSwitchKinds.has(String(pendingPromptCommand.kind || ''))) {
    return false;
  }

  lastExistingUsageLimitHandlerAt = Date.now();
  clearContinueTimer();
  clearPromptCommandTimer();
  clearStaticRecheckTimer();
  continueLoopArmed = false;
  reconcileModelIndexFromVisibleTerminal('usage limit handling', { allowBackward: false });
  if (!usageLimitSnapshotMatchesVisibleModel(snapshot)) return false;

  if (canAutoAdvanceUsageLimitModelChain()) {
    if (wasUsageLimitSnapshotHandledRecently(snapshot)) return false;
    markUsageLimitSnapshotHandled(snapshot);

    const forceRelaunch = shouldRelaunchForBlockedUsageLimit(snapshot);
    const reason = `Usage limit reached on ${currentModel()}`;

    if (snapshot.stopOption && !forceRelaunch) {
      const nextIndex = findNextEligibleModelIndex(modelIndex);
      pendingPromptCommand = {
        kind: 'usage-limit-stop-finalize',
        reason,
        targetIndex: nextIndex >= 0 ? nextIndex : undefined,
        targetModel: nextIndex >= 0 ? MODELS[nextIndex] : '',
        createdAt: Date.now(),
      };
      clearPendingPromptCommandNudgeTimer();
      console.error(`\n[${FLAVOR_LABEL}] ${reason} — selecting Stop before switching models.\n`);
      return runMenuPlanForOption(runId, snapshot, snapshot.stopOption, 'dismiss-usage-limit');
    }

    if (shouldSwitchImmediatelyForPromptUsageLimit(snapshot)) {
      requestModelAdvanceOrFinish(reason, {
        allowBackwardVisibleReconcile: false,
        retryInitialPromptAfterSwitch: shouldRetryInitialPromptAfterUsageLimit(),
        snapshot,
      });
      clearMenuPlan();
      return true;
    }

    if (forceRelaunch) {
      const nextIndex = findNextEligibleModelIndex(modelIndex);
      pendingPromptCommand = {
        kind: 'usage-limit-stop-finalize',
        reason,
        targetIndex: nextIndex >= 0 ? nextIndex : undefined,
        targetModel: nextIndex >= 0 ? MODELS[nextIndex] : '',
        createdAt: Date.now(),
      };
      clearPendingPromptCommandNudgeTimer();
      clearMenuPlan();
      console.error(`\n[${FLAVOR_LABEL}] ${reason} — waiting for the usage-limit Stop option before switching models.\n`);
      scheduleStaticRecheck(QUICK_RECHECK_MS);
      return true;
    }

    requestModelAdvanceOrFinish(reason, {
      forceRelaunch,
      forceRelaunchDetail: forceRelaunch ? 'usage limit screen has no Stop option' : '',
      allowBackwardVisibleReconcile: false,
      retryInitialPromptAfterSwitch: shouldRetryInitialPromptAfterUsageLimit(),
      snapshot,
    });
    clearMenuPlan();
    return true;
  }

  clearMenuPlan();
  if (AUTO_DISABLE_ON_USAGE_LIMIT && automationEnabled) {
    setAutomationEnabled(false, 'usage_limit');
    console.error(`\n[${FLAVOR_LABEL}] Usage limit detected — automation paused. ${hotkeySummary()}\n`);
  }
  return true;
}

function shouldRelaunchForBlockedUsageLimit(snapshot) {
  if (snapshot?.kind !== 'usage_limit') return false;
  return !snapshot?.stopOption;
}

function shouldSwitchImmediatelyForPromptUsageLimit(snapshot) {
  if (snapshot?.kind !== 'usage_limit') return false;
  if (snapshot?.stopOption) return false;
  return Boolean(snapshot?.usageLimitPromptActive);
}

function handleCapacityMenuSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'capacity_menu') return false;
  clearContinueTimer();
  clearPromptCommandTimer();

  const now = Date.now();
  if (lastCapacityAt > 0 && now - lastCapacityAt > CAPACITY_EVENT_RESET_MS) {
    demandHits = 0;
    autoContinueAttempts = 0;
  }
  lastCapacityAt = now;

  if (!NEVER_SWITCH && snapshot.switchOption && demandHits >= KEEP_TRY_MAX && !hasAnotherModelInChain()) {
    handleModelChainExhausted(`Capacity limit reached on ${currentModel()}`, { snapshot });
    return true;
  }

  let targetOption = snapshot.keepOption;
  let label = `keep-trying ${Math.min(demandHits + 1, KEEP_TRY_MAX)}/${KEEP_TRY_MAX}`;

  if (!NEVER_SWITCH && snapshot.switchOption && demandHits >= KEEP_TRY_MAX) {
    targetOption = snapshot.switchOption;
    label = 'switch-model';
  }

  if (hasActiveMenuPlan(snapshot, targetOption)) {
    return runMenuPlanForOption(runId, snapshot, targetOption, label);
  }

  if (now - lastDemandTs < TRY_AGAIN_MIN_INTERVAL_MS) return true;

  lastDemandTs = now;
  demandHits += 1;

  if (NEVER_SWITCH || !snapshot.switchOptionText) {
    if (demandHits > KEEP_TRY_MAX) {
      if (canAutoAdvanceModelChain()) {
        requestModelAdvanceOrFinish(`Capacity limit reached on ${currentModel()}`, { snapshot });
        return true;
      }
      pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, 'keep-trying loop limit reached');
      return true;
    }
    return runMenuPlanForOption(runId, snapshot, snapshot.keepOption, `keep-trying ${demandHits}/${KEEP_TRY_MAX}`);
  }

  if (demandHits <= KEEP_TRY_MAX) {
    return runMenuPlanForOption(runId, snapshot, snapshot.keepOption, `keep-trying ${demandHits}/${KEEP_TRY_MAX}`);
  }

  if (!hasAnotherModelInChain()) {
    handleModelChainExhausted(`Capacity limit reached on ${currentModel()}`, { snapshot });
    return true;
  }

  switching = true;
  console.error(`\n[${FLAVOR_LABEL}] Capacity still busy on ${currentModel()} — switching model...\n`);
  return runMenuPlanForOption(runId, snapshot, snapshot.switchOption, 'switch-model');
}

function handleCapacityContinueSnapshot(runId, snapshot) {
  if (snapshot.kind !== 'capacity_continue' && snapshot.kind !== 'capacity_info') return false;
  clearMenuPlan();

  if (!AUTO_CONTINUE_ON_CAPACITY || AUTO_CONTINUE_MODE === 'off') {
    clearContinueTimer();
    return true;
  }

  const explicitOnly = !(AUTO_CONTINUE_MODE === 'capacity' || AUTO_CONTINUE_MODE === 'always');
  if (explicitOnly && snapshot.kind !== 'capacity_continue') {
    clearContinueTimer();
    return true;
  }

  scheduleContinueRetry(runId, snapshot);
  return true;
}

function runMenuPlanForOption(runId, snapshot, targetOption, label) {
  if (runId !== activeRunId || !activePty) return false;
  if (!targetOption?.numberText || !targetOption?.canonical) return true;

  const target = snapshot.options.find(
    (option) => option.numberText === targetOption.numberText && option.canonical === targetOption.canonical
  ) || targetOption;

  const plan = ensureMenuPlan(snapshot, target, label);
  if (plan.totalActions >= MENU_ACTION_LIMIT) {
    pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, `${label} action limit reached`);
    return true;
  }

  const now = Date.now();
  const selected = snapshot.selectedOption || snapshot.options.find((option) => option.selected) || null;
  const selectedIndex = selected
    ? snapshot.options.findIndex(
        (option) => option.numberText === selected.numberText && option.canonical === selected.canonical
      )
    : -1;
  const targetIndex = snapshot.options.findIndex(
    (option) => option.numberText === target.numberText && option.canonical === target.canonical
  );

  if (snapshot.kind === 'capacity_menu' && Boolean(target.numberText && target.numberText.trim()) && plan.numericAttempts < MENU_NUMERIC_MAX_ATTEMPTS) {
    plan.phase = 'numeric';
    plan.numericAttempts += 1;
    plan.totalActions += 1;
    plan.lastSentAt = now;
    rememberAction(`${snapshot.kind}:${snapshot.fingerprint}:numeric:${target.numberText}`);
    sendChoice(target.numberText, `${label}:select-number`, runId);
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  const numericAllowed = snapshot.kind !== 'usage_limit'
    && !snapshot.chatPromptActive
    && Boolean(target.numberText && target.numberText.trim())
    && plan.numericAttempts < MENU_NUMERIC_MAX_ATTEMPTS;
  if (numericAllowed) {
    plan.phase = 'numeric';
    plan.numericAttempts += 1;
    plan.totalActions += 1;
    plan.lastSentAt = now;
    rememberAction(`${snapshot.kind}:${snapshot.fingerprint}:numeric:${target.numberText}`);
    sendChoice(target.numberText, `${label}:select-number`, runId);
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  if (snapshot.kind === 'usage_limit' && plan.navAttempts > 0) {
    if (plan.confirmAttempts >= MENU_CONFIRM_MAX_ATTEMPTS) {
      pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, `${label} confirm limit reached`);
      return true;
    }
    if (now - plan.lastSentAt < MENU_CONFIRM_MIN_MS) return true;
    plan.phase = 'confirm';
    plan.confirmAttempts += 1;
    plan.totalActions += 1;
    plan.lastSentAt = now;
    rememberAction(`${snapshot.kind}:${snapshot.fingerprint}:confirm-after-nav`);
    sendRaw('\r', `${label}:confirm-enter`);
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  if (target.selected) {
    if (plan.confirmAttempts >= MENU_CONFIRM_MAX_ATTEMPTS) {
      pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, `${label} confirm limit reached`);
      return true;
    }
    if (now - plan.lastSentAt < MENU_CONFIRM_MIN_MS) return true;
    plan.phase = 'confirm';
    plan.confirmAttempts += 1;
    plan.totalActions += 1;
    plan.lastSentAt = now;
    rememberAction(`${snapshot.kind}:${snapshot.fingerprint}:confirm`);
    sendRaw('\r', `${label}:confirm-enter`);
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  if (now - plan.lastSentAt < MENU_SELECT_MIN_MS) return true;

  if (selectedIndex >= 0 && targetIndex >= 0 && selectedIndex !== targetIndex) {
    if (plan.navAttempts >= MENU_NAV_MAX_ATTEMPTS) {
      pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, `${label} navigation limit reached`);
      return true;
    }
    const delta = targetIndex - selectedIndex;
    const navSequence = delta > 0 ? '\u001B[B'.repeat(delta) : '\u001B[A'.repeat(-delta);
    if (!navSequence) return true;
    plan.phase = 'nav';
    plan.navAttempts += 1;
    plan.totalActions += 1;
    plan.lastSentAt = now;
    rememberAction(`${snapshot.kind}:${snapshot.fingerprint}:nav:${delta}`);
    sendRaw(navSequence, `${label}:arrow-focus`);
    scheduleStaticRecheck(QUICK_RECHECK_MS);
    return true;
  }

  pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, `${label} could not safely focus target option`);
  return true;
}

function ensureMenuPlan(snapshot, target, label) {
  if (
    !menuPlan ||
    menuPlan.kind !== snapshot.kind ||
    menuPlan.fingerprint !== snapshot.fingerprint ||
    menuPlan.targetNumberText !== target.numberText ||
    menuPlan.targetCanonical !== target.canonical
  ) {
    menuPlan = {
      kind: snapshot.kind,
      fingerprint: snapshot.fingerprint,
      targetNumberText: target.numberText,
      targetCanonical: target.canonical,
      targetLabel: target.canonical,
      label,
      phase: 'select',
      numericAttempts: 0,
      navAttempts: 0,
      confirmAttempts: 0,
      totalActions: 0,
      lastSentAt: 0,
      createdAt: Date.now(),
    };
  }
  return menuPlan;
}

function clearMenuPlan() {
  menuPlan = null;
}

function hasActiveMenuPlan(snapshot, targetOption) {
  return Boolean(
    menuPlan &&
      menuPlan.kind === snapshot.kind &&
      menuPlan.fingerprint === snapshot.fingerprint &&
      menuPlan.targetNumberText === targetOption?.numberText &&
      menuPlan.targetCanonical === targetOption?.canonical
  );
}

function scheduleContinueRetry(runId, snapshot) {
  if (continueTimer) return;
  if (autoContinueAttempts >= AUTO_CONTINUE_MAX_PER_EVENT) {
    if (canAutoAdvanceModelChain() && snapshot.reason !== 'context window warning') {
    requestModelAdvanceOrFinish(`Too many auto-continues for ${snapshot.reason}`, { snapshot });
      return;
    }
    pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, `too many auto-continues for ${snapshot.reason}`);
    return;
  }

  const scheduledGeneration = stateGeneration;
  const delay = typeof snapshot.continueDelayMs === 'number'
    ? Math.max(0, snapshot.continueDelayMs)
    : Math.min(CAPACITY_RETRY_MS * 2 ** autoContinueAttempts, MAX_CAPACITY_RETRY_MS);
  const label = snapshot.kind === 'capacity_continue' && snapshot.continueAction === 'enter' ? 'Enter' : CONTINUE_COMMAND;
  console.error(`\n[${FLAVOR_LABEL}] ${snapshot.reason} — retrying in ${delay}ms (sending: ${label}) [${autoContinueAttempts + 1}/${AUTO_CONTINUE_MAX_PER_EVENT}]\n`);

  continueTimer = setTimeout(() => {
    continueTimer = null;
    if (runId !== activeRunId || !activePty || !isAutomationActive()) return;
    if (scheduledGeneration !== stateGeneration) return;

    const latest = detectCurrentSnapshot();
    updateCurrentSnapshot(latest);
    if (latest.kind !== currentSnapshot.kind || latest.fingerprint !== currentSnapshot.fingerprint) return;
    if (AUTO_CONTINUE_MODE !== 'capacity' && AUTO_CONTINUE_MODE !== 'always' && latest.kind !== 'capacity_continue') return;

    autoContinueAttempts += 1;
    if (latest.kind === 'capacity_continue' && latest.continueAction === 'enter') {
      sendChoice('', latest.reason, runId);
    } else {
      sendChoice(CONTINUE_COMMAND, latest.reason, runId);
    }
    scheduleStaticRecheck(QUICK_RECHECK_MS);
  }, delay);
}

function buildModelSwitchCommand(model) {
  const targetModel = String(model || '').trim();
  if (!targetModel) return '';

  if (!MODEL_SWITCH_COMMAND_TEMPLATE) {
    return `/model set ${targetModel}`;
  }

  return MODEL_SWITCH_COMMAND_TEMPLATE.includes('{model}')
    ? MODEL_SWITCH_COMMAND_TEMPLATE.replaceAll('{model}', targetModel)
    : `${MODEL_SWITCH_COMMAND_TEMPLATE} ${targetModel}`.trim();
}

function fallbackPendingModelManageFlow(reason) {
  if (!pendingPromptCommand) return false;

  const targetIndex = pendingPromptCommand.targetIndex;
  const targetModel = pendingPromptCommand.targetModel;
  const advanceReason = pendingPromptCommand.advanceReason;
  const retryInitialPromptAfterSwitch = pendingPromptCommand.retryInitialPromptAfterSwitch === true;
  if (!Number.isInteger(targetIndex) || !targetModel) {
    pendingPromptCommand = null;
    return false;
  }

  pendingPromptCommand = {
    kind: 'model-switch',
    text: buildModelSwitchCommand(targetModel),
    reason: `model-switch ${targetModel}`,
    label: `/model set ${targetModel}`,
    targetIndex,
    targetModel,
    advanceReason,
    retryInitialPromptAfterSwitch,
    createdAt: Date.now(),
  };
  console.error(`\n[${FLAVOR_LABEL}] ${reason} — falling back to direct model switch for ${targetModel}.\n`);
  recheckVisiblePrompt('model manage fallback');
  return true;
}

function relaunchPendingModelManageTarget(reason) {
  if (!pendingPromptCommand) return false;

  const targetIndex = pendingPromptCommand.targetIndex;
  const targetModel = pendingPromptCommand.targetModel;
  pendingPromptCommand = null;

  if (!Number.isInteger(targetIndex) || !targetModel || targetIndex < 0 || targetIndex >= MODELS.length) {
    return false;
  }

  modelIndex = targetIndex;
  console.error(`\n[${FLAVOR_LABEL}] ${reason} — relaunching directly on ${targetModel}.\n`);
  requestLauncherAction('restart');
  return true;
}

function queueModelSwitchCommand(targetIndex, reason, options = {}) {
  const index = Number(targetIndex);
  if (!Number.isInteger(index) || index < 0 || index >= MODELS.length) return false;

  const targetModel = MODELS[index];
  if (pendingPromptCommand?.targetIndex === index) {
    return true;
  }

  if (MODEL_SWITCH_MODE === 'manage') {
    const command = buildModelManageStarterCommand(index, targetModel, currentGeminiCliCapabilities, {
      advanceReason: reason,
      retryInitialPromptAfterSwitch: options.retryInitialPromptAfterSwitch === true,
    });
    if (!command) return false;
    clearPromptCommandTimer();
    clearPendingPromptCommandNudgeTimer();
    pendingPromptCommand = command;
    if (command.kind === 'stats-session') {
      console.error(`\n[${FLAVOR_LABEL}] ${reason} — queueing /stats session and /model manage for ${targetModel}.\n`);
    } else {
      const skipReason = currentGeminiCliCapabilities.statsSessionAutomationDisabledReason || 'unsupported by this Gemini CLI build';
      console.error(`\n[${FLAVOR_LABEL}] ${reason} — queueing /model manage for ${targetModel} (${skipReason}).\n`);
    }
    return true;
  }

  return queueDirectModelSwitchCommand(index, reason, options);
}

function queueDirectModelSwitchCommand(targetIndex, reason, options = {}) {
  const index = Number(targetIndex);
  if (!Number.isInteger(index) || index < 0 || index >= MODELS.length) return false;

  if (pendingPromptCommand?.targetIndex === index) {
    return true;
  }

  const command = buildDirectModelSwitchCommand(index, reason, MODELS, {
    advanceReason: reason,
    retryInitialPromptAfterSwitch: options.retryInitialPromptAfterSwitch === true,
  });
  if (!command) return false;
  clearPromptCommandTimer();
  clearPendingPromptCommandNudgeTimer();
  pendingPromptCommand = command;
  console.error(`\n[${FLAVOR_LABEL}] ${reason} — queueing in-session switch to ${command.targetModel}.\n`);
  return true;
}

function buildDirectModelSwitchCommand(targetIndex, reason, models = MODELS, options = {}) {
  const index = Number(targetIndex);
  const chain = Array.isArray(models) ? models : [];
  if (!Number.isInteger(index) || index < 0 || index >= chain.length) return null;

  const targetModel = String(chain[index] || '').trim();
  if (!targetModel) return null;

  const text = buildModelSwitchCommand(targetModel);
  if (!text) return null;

  return {
    kind: 'model-switch',
    text,
    reason: `model-switch ${targetModel}`,
    label: `/model set ${targetModel}`,
    targetIndex: index,
    targetModel,
    advanceReason: options.advanceReason || reason,
    retryInitialPromptAfterSwitch: options.retryInitialPromptAfterSwitch === true,
    createdAt: Date.now(),
  };
}

function schedulePromptCommand(runId, snapshot, command) {
  if (runId !== activeRunId || !activePty) return false;
  if (!snapshot?.chatPromptActive && !canSendPromptCommandWithoutVisiblePrompt(command, snapshot)) return false;

  const promptFingerprint = String(command?.promptFingerprint || snapshot?.promptFingerprint || snapshot?.fingerprint || '').trim();
  if (command?.kind === 'continue' && !promptFingerprint) return false;

  const text = String(command?.text || '').trim();
  if (!text) return false;

  const nextPriority = promptCommandPriority(command?.kind);
  const scheduledPriority = promptCommandPriority(scheduledPromptCommand?.kind);
  if (promptCommandTimer) {
    if (nextPriority > scheduledPriority) {
      if (DEBUG_AUTOMATION) {
        console.error(`[${FLAVOR_LABEL}][prompt] preempting ${scheduledPromptCommand?.kind || 'unknown'} with ${command?.kind || 'unknown'}`);
      }
      clearPromptCommandTimer();
    } else {
      return true;
    }
  }

  const dedupeKey = `${command.kind}:${promptFingerprint}:${text}`;
  if (actionSeenRecently(dedupeKey, ACTION_RETRY_MIN_MS)) return true;

  const quietForMs = Date.now() - lastTerminalDataAt;
  const delay = promptCommandScheduleDelay(command, snapshot, quietForMs);
  const label = command.label || text;
  scheduledPromptCommand = {
    kind: command.kind,
    text,
    reason: command.reason || command.kind,
  };

  promptCommandTimer = setTimeout(() => {
    promptCommandTimer = null;
    scheduledPromptCommand = null;
    if (runId !== activeRunId || !activePty || !isAutomationActive()) return;
    if (!isPromptCommandStillCurrent(command)) return;

    const latest = detectCurrentSnapshot();
    updateCurrentSnapshot(latest);
    const canSendWithoutVisiblePrompt = canSendPromptCommandWithoutVisiblePrompt(command, latest);
    if (!latest.chatPromptActive && !canSendWithoutVisiblePrompt) return;
    if (command.kind === 'continue' && latest.kind !== 'normal') return;
    if (command.kind === 'continue' && latest.promptFingerprint !== promptFingerprint) return;
    if (command.kind === 'model-manage-open' && latest.kind !== 'normal' && latest.kind !== 'usage_limit') return;

    const latestPromptInputText = promptInputTextFromSnapshot(latest);
    if (requiresEmptyPromptInputForCommand(command)) {
      if (hasPendingSubmitEnter()) {
        scheduleStaticRecheck(QUICK_RECHECK_MS);
        return;
      }
      if (latestPromptInputText) {
        if (isLikelyAutomationPromptInput(latestPromptInputText)) {
          queueStartupPromptInputClear(`stale automated prompt input before ${command.label || command.text || command.kind}`, command);
        }
        return;
      }
    }

    const promptCommandSendDetail = describePromptCommandSendDetail(command, latest);
    if (promptCommandSendDetail) {
      const prefix = command.kind === 'startup-clear' || command.kind === 'startup-stats' || command.kind === 'startup-model' ? 'startup ' : '';
      console.error(`\n[${FLAVOR_LABEL}] Auto-sending ${prefix}${label} (${promptCommandSendDetail})...\n`);
    }

    const submitSettlesAt = promptCommandSubmitSettleDeadline(text, command);
    const sent = sendChoice(text, command.reason || command.kind, runId, {
      armContinueLoop: command.kind === 'continue',
      commandKind: command.kind,
    });
    if (!sent) return;

    rememberAction(dedupeKey);
    if (command.kind === 'startup-clear') {
      pendingPromptCommand = {
        kind: 'startup-clear-finalize',
        text,
        label,
        detail: promptCommandSendDetail || label,
        createdAt: Date.now(),
        submitSettlesAt,
      };
    } else if (command.kind === 'startup-stats') {
      pendingPromptCommand = {
        kind: 'startup-stats-finalize',
        text,
        label,
        fallbackText: command.fallbackText,
        fallbackUsed: command.fallbackUsed === true,
        createdAt: Date.now(),
        submitSettlesAt,
      };
    } else if (command.kind === 'startup-model') {
      startupModelCapacityObserved = false;
      startupModelCapacitySnapshot = null;
      pendingPromptCommand = {
        kind: 'startup-model-finalize',
        text,
        label,
        createdAt: Date.now(),
        closeSentAt: 0,
        submitSettlesAt,
      };
    } else if (command.kind === 'stats-session') {
      pendingPromptCommand = {
        kind: 'model-manage-open',
        text: MODEL_MANAGE_COMMAND,
        reason: `open model manage for ${command.targetModel || 'target model'}`,
        label: MODEL_MANAGE_COMMAND,
        targetIndex: command.targetIndex,
        targetModel: command.targetModel,
        advanceReason: command.advanceReason,
        retryInitialPromptAfterSwitch: command.retryInitialPromptAfterSwitch === true,
        createdAt: Date.now(),
        submitSettlesAt,
      };
      schedulePendingPromptCommandNudge(runId, PROMPT_COMMAND_SETTLE_MS + 250, 'post-stats-session');
    } else if (command.kind === 'model-manage-open') {
      pendingPromptCommand = {
        kind: 'model-manage-route',
        targetIndex: command.targetIndex,
        targetModel: command.targetModel,
        advanceReason: command.advanceReason,
        retryInitialPromptAfterSwitch: command.retryInitialPromptAfterSwitch === true,
        createdAt: Date.now(),
        submitSettlesAt,
      };
    } else if (command.kind === 'model-switch' && Number.isInteger(command.targetIndex)) {
      pendingPromptCommand = {
        kind: 'model-switch-finalize',
        text,
        label,
        targetIndex: command.targetIndex,
        targetModel: command.targetModel,
        advanceReason: command.advanceReason,
        retryInitialPromptAfterSwitch: command.retryInitialPromptAfterSwitch === true,
        createdAt: Date.now(),
        submitSettlesAt: 0,
      };
    } else if (command.kind === 'auth') {
      pendingPromptCommand = null;
      authHandoffInProgress = true;
      sentInitialPrompt = true;
      continueLoopArmed = false;
      clearInitialPromptTimer();
      console.error(`\n[${FLAVOR_LABEL}] Authentication handoff started with ${text}. Waiting for account change completion.\n`);
    }
    scheduleStaticRecheck(QUICK_RECHECK_MS);
  }, delay);

  if (DEBUG_AUTOMATION) {
    console.error(`[${FLAVOR_LABEL}][prompt] scheduling ${JSON.stringify(text)} in ${delay}ms (${command.kind})`);
  }
  return true;
}

function promptCommandScheduleDelay(command, snapshot, quietForMs = Date.now() - lastTerminalDataAt) {
  const kind = String(command?.kind || '').trim();
  const settleMs = snapshot?.chatPromptActive && isStartupPromptCommandKind(kind)
    ? STARTUP_VISIBLE_PROMPT_COMMAND_SETTLE_MS
    : PROMPT_COMMAND_SETTLE_MS;
  return Math.max(30, settleMs - Math.max(0, quietForMs));
}

function requiresEmptyPromptInputForCommand(command) {
  const text = String(command?.text || '').trim();
  if (String(command?.kind || '').trim() === 'continue') return true;
  if (!text.startsWith('/')) return false;

  return [
    'startup-clear',
    'startup-stats',
    'startup-model',
    'stats-session',
    'model-manage-open',
    'model-switch',
    'auth',
  ].includes(String(command?.kind || '').trim());
}

function promptCommandSubmitSettleDeadline(text, command) {
  const reason = command?.reason || command?.kind || '';
  const commandKind = command?.kind || '';
  const processingGraceMs = promptSubmitProcessingGraceForKind(commandKind, reason);
  if (requiresEmptyPromptInputForCommand(command)) {
    return Date.now() + Math.max(0, PROMPT_SUBMIT_DELAY_MS) + PROMPT_SUBMIT_SETTLE_MS + processingGraceMs;
  }

  if (!shouldSubmitWithDelayedEnter(text, reason, { commandKind })) return 0;
  return Date.now() + PROMPT_SUBMIT_DELAY_MS + PROMPT_SUBMIT_SETTLE_MS + processingGraceMs;
}

function isPromptCommandSubmitSettling(command, now = Date.now()) {
  if (hasPendingSubmitEnter({ now })) return true;
  const notBeforeAt = Number(command?.notBeforeAt || 0);
  if (Number.isFinite(notBeforeAt) && notBeforeAt > now) return true;
  const deadline = Number(command?.submitSettlesAt || 0);
  if (Number.isFinite(deadline) && deadline > now) return true;

  const minimumSettleMs = pendingPromptCommandMinimumSubmitSettleMs(command);
  const createdAt = Number(command?.createdAt || 0);
  return minimumSettleMs > 0 && Number.isFinite(createdAt) && createdAt > 0 && now - createdAt < minimumSettleMs;
}

function pendingPromptCommandMinimumSubmitSettleMs(command) {
  const kind = String(command?.kind || '').trim();
  if ([
    'startup-clear-finalize',
    'startup-stats-finalize',
    'startup-model-finalize',
  ].includes(kind)) {
    return Math.max(0, PROMPT_SUBMIT_DELAY_MS) + PROMPT_SUBMIT_SETTLE_MS + PROMPT_SUBMIT_PROCESSING_GRACE_MS;
  }

  if ([
    'model-manage-open',
    'model-manage-route',
  ].includes(kind)) {
    return Math.max(0, PROMPT_SUBMIT_DELAY_MS) + PROMPT_SUBMIT_SETTLE_MS;
  }

  return 0;
}

function delayPromptCommandAfterSlashSubmit(command) {
  if (!command) return null;
  const delayMs = startupSlashHandoffDelayMs();
  return {
    ...command,
    notBeforeAt: Math.max(Number(command.notBeforeAt || 0), Date.now() + delayMs),
  };
}

function startupSlashHandoffDelayMs() {
  return Math.max(
    500,
    PROMPT_COMMAND_SETTLE_MS,
    Math.max(0, PROMPT_SUBMIT_DELAY_MS) + Math.min(Math.max(0, PROMPT_SUBMIT_SETTLE_MS), 320)
  );
}

function promptSubmitProcessingGraceForKind(kind, reason = '') {
  const commandKind = String(kind || '').trim();
  const normalizedReason = String(reason || '').trim();
  if (
    commandKind === 'startup-clear' ||
    commandKind === 'startup-stats' ||
    commandKind === 'startup-model' ||
    normalizedReason === 'startup clear' ||
    normalizedReason === 'startup session stats capture' ||
    normalizedReason === 'startup model capacity capture'
  ) {
    return PROMPT_SUBMIT_PROCESSING_GRACE_MS;
  }
  return 0;
}

function describePromptCommandSendDetail(command, snapshot, options = {}) {
  const kind = String(command?.kind || '').trim();
  if (kind !== 'startup-clear' && kind !== 'startup-stats' && kind !== 'startup-model' && kind !== 'stats-session' && kind !== 'auth') {
    return '';
  }

  const now = Number.isFinite(options.now) ? Number(options.now) : Date.now();
  const quietForMs = Number.isFinite(options.quietForMs)
    ? Math.max(0, Number(options.quietForMs))
    : Math.max(0, now - lastTerminalDataAt);
  const waitedForMs = Number.isFinite(options.waitedForMs)
    ? Math.max(0, Number(options.waitedForMs))
    : Math.max(0, now - Number(command?.createdAt || now));

  if (snapshot?.chatPromptActive) return 'visible prompt field';
  if (quietForMs >= PROMPT_COMMAND_SETTLE_MS) return `settled normal screen (${quietForMs}ms quiet)`;
  return `prompt timeout (${waitedForMs}ms)`;
}

function isPromptCommandStillCurrent(command, pending = pendingPromptCommand) {
  const kind = String(command?.kind || '').trim();
  if (!kind) return false;
  if (kind === 'continue') return true;

  const current = pending && typeof pending === 'object' ? pending : null;
  if (!current) return false;
  if (String(current.kind || '').trim() !== kind) return false;

  const commandText = String(command?.text || '').trim();
  const currentText = String(current.text || '').trim();
  if ((commandText || currentText) && commandText !== currentText) return false;

  const commandTargetIndex = Number(command?.targetIndex);
  const currentTargetIndex = Number(current.targetIndex);
  if ((Number.isInteger(commandTargetIndex) || Number.isInteger(currentTargetIndex)) &&
      commandTargetIndex !== currentTargetIndex) {
    return false;
  }

  const commandTargetModel = String(command?.targetModel || '').trim();
  const currentTargetModel = String(current.targetModel || '').trim();
  if ((commandTargetModel || currentTargetModel) && commandTargetModel !== currentTargetModel) return false;

  return true;
}

function promptCommandPriority(kind) {
  switch (String(kind || '')) {
    case 'stats-session':
    case 'model-manage-open':
    case 'model-switch':
      return 4;
    case 'startup-clear':
    case 'startup-stats':
    case 'startup-model':
      return 3;
    case 'continue':
      return 1;
    default:
      return 2;
  }
}

function canSendPromptCommandWithoutVisiblePrompt(command, snapshot, options = {}) {
  if (snapshot?.chatPromptActive) return true;

  const kind = String(command?.kind || '').trim();
  if (kind !== 'startup-clear' && kind !== 'startup-stats' && kind !== 'startup-model' && kind !== 'stats-session') return false;
  if (snapshot?.kind !== 'normal') return false;

  const authWaiting = options.authWaiting ?? (authWaitSince > 0);
  if (authWaiting) return false;
  const promptReadySurface = Object.prototype.hasOwnProperty.call(options, 'promptReadySurface')
    ? Boolean(options.promptReadySurface)
    : hasInitialPromptReadySurface(snapshot);
  if (!promptReadySurface) return false;

  const quietForMs = Number.isFinite(options.quietForMs)
    ? Number(options.quietForMs)
    : Math.max(0, Date.now() - lastTerminalDataAt);
  const waitedForMs = Number.isFinite(options.waitedForMs)
    ? Number(options.waitedForMs)
    : Math.max(0, Date.now() - Number(command?.createdAt || Date.now()));

  return quietForMs >= PROMPT_COMMAND_SETTLE_MS || waitedForMs >= INITIAL_PROMPT_MAX_WAIT_MS;
}

function hasStartupClearSettled(snapshot, options = {}) {
  if (snapshot?.kind !== 'normal') return false;
  if (hasPendingSubmitEnter(options)) return false;
  const submitSettlesAt = Number(options.submitSettlesAt || 0);
  if (Number.isFinite(submitSettlesAt) && submitSettlesAt > Date.now()) return false;
  const submittedAt = Number(options.submittedAt || 0);
  if (Number.isFinite(submittedAt) && submittedAt > 0 && lastTerminalDataAt < submittedAt) return false;
  const waitedForMs = Number.isFinite(options.waitedForMs)
    ? Number(options.waitedForMs)
    : 0;
  const minimumCommandWaitMs = startupSlashHandoffDelayMs();
  if (waitedForMs < minimumCommandWaitMs) return false;
  if (promptInputTextFromSnapshot(snapshot)) return false;
  const screenText = String(options.screenText || '').trim();
  const visibleText = String(options.visibleText || '').trim();
  if (snapshot?.chatPromptActive) return true;

  if (extractStartupStatsSnapshot(screenText || visibleText)) return false;

  const quietForMs = Number.isFinite(options.quietForMs)
    ? Number(options.quietForMs)
    : Math.max(0, Date.now() - lastTerminalDataAt);
  return quietForMs >= PROMPT_COMMAND_SETTLE_MS || waitedForMs >= INITIAL_PROMPT_MAX_WAIT_MS;
}

function hasStartupStatsCaptureSettled(snapshot, options = {}) {
  if (!options.startupStatsObserved) return false;
  if (snapshot?.kind !== 'normal') return false;
  if (hasPendingSubmitEnter(options)) return false;
  const submitSettlesAt = Number(options.submitSettlesAt || 0);
  if (Number.isFinite(submitSettlesAt) && submitSettlesAt > Date.now()) return false;
  if (promptInputTextFromSnapshot(snapshot)) return false;

  const screenText = String(options.screenText || '').trim();
  const visibleText = String(options.visibleText || '').trim();
  const activeVisibleText = screenText || visibleText;
  if (activeVisibleText && extractStartupStatsSnapshot(activeVisibleText)) return false;
  if (snapshot?.chatPromptActive) return true;

  const quietForMs = Number.isFinite(options.quietForMs)
    ? Number(options.quietForMs)
    : Math.max(0, Date.now() - lastTerminalDataAt);
  const waitedForMs = Number.isFinite(options.waitedForMs)
    ? Number(options.waitedForMs)
    : 0;

  return quietForMs >= INITIAL_PROMPT_SETTLE_MS || waitedForMs >= INITIAL_PROMPT_MAX_WAIT_MS;
}

function hasStartupModelCapacityClosed(snapshot, options = {}) {
  if (snapshot?.kind !== 'normal') return false;
  if (hasPendingSubmitEnter(options)) return false;
  if (promptInputTextFromSnapshot(snapshot)) return false;

  const screenText = String(options.screenText || '').trim();
  const visibleText = String(options.visibleText || '').trim();
  const activeVisibleText = screenText || visibleText;
  if (activeVisibleText && extractStartupModelCapacitySnapshot(activeVisibleText)) return false;
  if (snapshot?.chatPromptActive) return true;

  const quietForMs = Number.isFinite(options.quietForMs)
    ? Number(options.quietForMs)
    : Math.max(0, Date.now() - lastTerminalDataAt);
  const waitedForMs = Number.isFinite(options.waitedForMs)
    ? Number(options.waitedForMs)
    : 0;

  return quietForMs >= INITIAL_PROMPT_SETTLE_MS || waitedForMs >= INITIAL_PROMPT_MAX_WAIT_MS;
}

function hasPendingSubmitEnter(options = {}) {
  if (Object.prototype.hasOwnProperty.call(options, 'pendingSubmitEnter')) {
    return Boolean(options.pendingSubmitEnter);
  }
  if (Object.prototype.hasOwnProperty.call(options, 'pendingSubmitSettling')) {
    return Boolean(options.pendingSubmitSettling);
  }

  const now = Number.isFinite(options.now) ? Number(options.now) : Date.now();
  return pendingSubmitTimers.size > 0 || now < pendingSubmitSettleUntil;
}

function describeStartupStatsCapture(snapshot) {
  const sessionID = String(snapshot?.sessionID || '').trim();
  const tier = String(snapshot?.tier || '').trim();
  const authMethod = String(snapshot?.authMethod || '').trim();

  const parts = [];
  if (sessionID) parts.push(`session ${sessionID}`);
  if (tier) parts.push(`tier ${tier}`);
  if (authMethod) parts.push(authMethod);

  return parts.join(', ') || 'session metadata recorded';
}

function describeStartupModelCapacityCapture(snapshot) {
  const rows = Array.isArray(snapshot?.rows) ? snapshot.rows : [];
  const currentModel = String(snapshot?.currentModel || '').trim();
  const rowSummary = rows
    .map((row) => {
      const model = String(row?.model || '').trim();
      const used = Number.isFinite(row?.usedPercentage) ? `${row.usedPercentage}% used` : '';
      return [model, used].filter(Boolean).join(' ');
    })
    .filter(Boolean)
    .join(', ');

  if (currentModel && rowSummary) return `current ${currentModel}; ${rowSummary}`;
  if (rowSummary) return rowSummary;
  if (currentModel) return `current ${currentModel}`;
  return 'model quota panel recorded';
}

function resolveStatsSessionFallbackCommand(primaryCommand = STATS_SESSION_COMMAND) {
  const fallback = String(STATS_SESSION_FALLBACK_COMMAND || '').trim();
  const primary = String(primaryCommand || '').trim();
  if (!fallback || fallback === primary) return '';
  return fallback;
}

function resolvePendingModelManageRecoveryAction({
  pendingKind,
  snapshotKind,
  chatPromptActive,
  authWaiting,
  elapsedMs,
  timeoutMs,
}) {
  if (
    pendingKind !== 'model-manage-open' &&
    pendingKind !== 'model-manage-route' &&
    pendingKind !== 'model-manage-select'
  ) {
    return 'none';
  }

  if (snapshotKind === 'model_manage_routing' || snapshotKind === 'model_manage_models') {
    return 'none';
  }

  if (!Number.isFinite(elapsedMs) || elapsedMs < timeoutMs) {
    return 'none';
  }

  if (chatPromptActive) {
    return 'direct-switch';
  }

  if (authWaiting) {
    return 'relaunch-target';
  }

  return 'relaunch-target';
}

function schedulePendingPromptCommandNudge(runId, delayMs, reason) {
  clearPendingPromptCommandNudgeTimer();
  pendingPromptCommandNudgeTimer = setTimeout(() => {
    pendingPromptCommandNudgeTimer = null;
    if (runId !== activeRunId || !activePty || !isAutomationActive()) return;
    if (!pendingPromptCommand || pendingPromptCommand.kind !== 'model-manage-open') return;

    const latest = detectCurrentSnapshot();
    updateCurrentSnapshot(latest);
    if (!latest.chatPromptActive) return;
    if (DEBUG_AUTOMATION) {
      console.error(`[${FLAVOR_LABEL}][prompt] nudging ${pendingPromptCommand.kind} after ${reason}`);
    }
    schedulePromptCommand(runId, latest, pendingPromptCommand);
  }, Math.max(30, delayMs));
}

function rememberAction(key) {
  recentActionKeys.set(key, Date.now());
}

function actionSeenRecently(key, ttlMs) {
  const ts = recentActionKeys.get(key);
  return typeof ts === 'number' && Date.now() - ts < ttlMs;
}

function usageLimitActionKey(snapshot) {
  if (snapshot?.kind !== 'usage_limit') return '';
  const fingerprint = String(snapshot?.fingerprint || '').trim();
  return fingerprint ? `usage-limit:${fingerprint}` : '';
}

function markUsageLimitSnapshotHandled(snapshot) {
  const key = usageLimitActionKey(snapshot);
  if (key) rememberAction(key);
}

function wasUsageLimitSnapshotHandledRecently(snapshot) {
  const key = usageLimitActionKey(snapshot);
  return Boolean(key && actionSeenRecently(key, USAGE_LIMIT_ACTION_TTL_MS));
}

function handleChildExit({ runId, exitCode, signal }) {
  console.error(`\n[child] exited: code=${exitCode} signal=${signal}\n`);
  lastChildExitAt = Date.now();

  if (plannedAction) {
    const action = plannedAction;
    plannedAction = null;
    if (action.kind === 'switch') {
      const nextIndex = findNextEligibleModelIndex(modelIndex);
      if (nextIndex < 0) {
        finishSessionAfterModelChainExhaustion();
        return;
      }
      modelIndex = nextIndex;
      spawnGemini();
      return;
    }
    if (action.kind === 'restart') {
      spawnGemini();
      return;
    }
    if (action.kind === 'finish') {
      cleanupAndExit(action.code ?? SESSION_COMPLETE_HOLD_OPEN_EXIT_CODE);
      return;
    }
    cleanupAndExit(action.code ?? 0);
    return;
  }

  if (pendingPromptCommand?.targetIndex != null && pendingPromptCommand?.targetModel) {
    const targetIndex = pendingPromptCommand.targetIndex;
    const targetModel = pendingPromptCommand.targetModel;
    pendingPromptCommand = null;

    if (Number.isInteger(targetIndex) && targetIndex >= 0 && targetIndex < MODELS.length) {
      modelIndex = targetIndex;
      console.error(`\n[${FLAVOR_LABEL}] Child exited while switching models — relaunching on ${targetModel}.\n`);
      spawnGemini();
      return;
    }
  }

  if (authRestartTelemetryPending) {
    pendingPromptCommand = null;
    console.error(`\n[${FLAVOR_LABEL}] Gemini exited during account-change restart — relaunching without startup ${STARTUP_CLEAR_COMMAND || '/clear'}.\n`);
    spawnGemini();
    return;
  }

  if (resumeEnabledThisRun && (exitCode === 42 || sawNoResumeSession)) {
    console.error(`[${FLAVOR_LABEL}] No resumable session — retrying without --resume\n`);
    resumeEnabledThisRun = false;
    spawnGemini();
    return;
  }

  if (switching) {
    switching = false;
    const nextIndex = findNextEligibleModelIndex(modelIndex);
    if (nextIndex < 0) {
      finishSessionAfterModelChainExhaustion();
      return;
    }
    modelIndex = nextIndex;
    spawnGemini();
    return;
  }

  if (yoloEnabledForSession && exitCode === 52) {
    yoloEnabledForSession = false;
    console.error(`[${FLAVOR_LABEL}] Gemini exited with a fatal config error while YOLO mode was enabled — retrying once without --yolo.\n`);
    spawnGemini();
    return;
  }

  const canAutoRestart =
    loadedPty &&
    automationEnabled &&
    automationDisabledReason !== 'usage_limit' &&
    lastCapacityAt > 0 &&
    Date.now() - lastCapacityAt <= CAPACITY_RECENT_MS;

  if (canAutoRestart) {
    if (!recordAutoRestart()) {
      console.error(`\n[${FLAVOR_LABEL}] Too many auto-restarts in a short window — stopping the loop. ${hotkeySummary()}\n`);
      cleanupAndExit(typeof exitCode === 'number' ? exitCode : 1);
      return;
    }

    console.error(`[${FLAVOR_LABEL}] Exited during/after capacity event — restarting in ${CAPACITY_RETRY_MS}ms...\n`);
    restartTimer = setTimeout(() => {
      restartTimer = null;
      if (runId !== activeRunId || shuttingDown) return;
      spawnGemini();
    }, CAPACITY_RETRY_MS);
    return;
  }

  cleanupAndExit(typeof exitCode === 'number' ? exitCode : 0);
}

function shouldIgnoreProcessSighupForState({
  shuttingDown: isShuttingDown,
  hasActiveSession,
  hasTransitioningAction,
  lastChildExitAt: childExitAt,
  now,
  graceMs,
}) {
  if (isShuttingDown) return false;
  if (hasActiveSession) return true;
  if (hasTransitioningAction) return true;
  if (childExitAt > 0 && now - childExitAt <= graceMs) return true;
  return false;
}

function shouldIgnoreProcessSighup() {
  return shouldIgnoreProcessSighupForState({
    shuttingDown,
    hasActiveSession: Boolean(activePty || activeChild),
    hasTransitioningAction: Boolean(plannedAction || pendingPromptCommand || switching),
    lastChildExitAt,
    now: Date.now(),
    graceMs: IGNORE_SIGHUP_GRACE_MS,
  });
}

function handleProcessSighup() {
  if (shouldIgnoreProcessSighup()) {
    console.error(`[${FLAVOR_LABEL}] Ignoring transient SIGHUP while a session is active or restarting.`);
    return;
  }
  cleanupAndExit(129);
}

function recordAutoRestart() {
  const now = Date.now();
  autoRestartHistory = autoRestartHistory.filter((ts) => now - ts <= AUTO_RESTART_WINDOW_MS);
  if (autoRestartHistory.length >= AUTO_RESTART_MAX_PER_WINDOW) return false;
  autoRestartHistory.push(now);
  return true;
}

function bindUserInput() {
  if (stdinBound) return;
  stdinBound = true;

  process.stdin.resume();
  if (process.stdin.isTTY) process.stdin.setRawMode?.(true);
  process.stdin.on('data', onUserInput);
  process.stdin.on('end', onStdinEnd);
}

function unbindUserInput() {
  if (!stdinBound) return;
  stdinBound = false;
  process.stdin.off('data', onUserInput);
  process.stdin.off('end', onStdinEnd);
  if (process.stdin.isTTY) {
    try {
      process.stdin.setRawMode?.(false);
    } catch {
      // ignore
    }
  }
}

function onUserInput(chunk) {
  const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk), 'utf8');
  if (buffer.length === 0) return;

  const forwardBytes = [];
  for (const byte of buffer.values()) {
    if (hotkeyAwaitingCommand) {
      hotkeyAwaitingCommand = false;
      clearHotkeyTimer();
      handleHotkeyCommand(byte);
      continue;
    }

    if (byte === HOTKEY_PREFIX_BYTE) {
      hotkeyAwaitingCommand = true;
      armHotkeyTimer();
      process.stderr.write(`\n[local] Prefix detected (${HOTKEY_PREFIX_LABEL}). Press h help, a auto toggle, o enable, x disable, p pause, e recheck, i status, s switch, r restart, c Ctrl-C, q quit.\n`);
      continue;
    }

    noteManualInput();
    forwardBytes.push(byte);
  }

  if (forwardBytes.length > 0 && activePty) {
    try {
      if (manualInputSubmitsPrompt(forwardBytes)) {
        continueLoopArmed = true;
      }
      activePty.write(Buffer.from(forwardBytes).toString('utf8'));
    } catch {
      // ignore
    }
  }
}

function onStdinEnd() {
  if (!activePty) return;
  try {
    activePty.write('\x04');
  } catch {
    // ignore
  }
}

function armHotkeyTimer() {
  clearHotkeyTimer();
  hotkeyTimer = setTimeout(() => {
    hotkeyTimer = null;
    if (!hotkeyAwaitingCommand) return;
    hotkeyAwaitingCommand = false;
    process.stderr.write(`\n[local] Hotkey prefix timed out. ${hotkeySummary()}\n`);
  }, HOTKEY_TIMEOUT_MS);
}

function clearHotkeyTimer() {
  if (!hotkeyTimer) return;
  clearTimeout(hotkeyTimer);
  hotkeyTimer = null;
}

function decodeHotkeyCommandByte(byte) {
  if (byte >= 1 && byte <= 26) return String.fromCharCode(96 + byte);
  return String.fromCharCode(byte).toLowerCase();
}

function handleHotkeyCommand(byte) {
  const command = decodeHotkeyCommandByte(byte);

  if (command === 'h' || command === '?') {
    printLocalHelp();
    return;
  }

  if (command === 'a') {
    if (automationEnabled) {
      setAutomationEnabled(false, 'manual');
      console.error(`\n[local] Automation disabled. ${HOTKEY_PREFIX_LABEL} a to re-enable.\n`);
    } else {
      setAutomationEnabled(true);
      console.error(`\n[local] Automation enabled; continuous ${CONTINUE_COMMAND} mode armed.\n`);
    }
    return;
  }

  if (command === 'o') {
    setAutomationEnabled(true, 'manual');
    console.error(`\n[local] Automation enabled; continuous ${CONTINUE_COMMAND} mode armed.\n`);
    return;
  }

  if (command === 'x') {
    setAutomationEnabled(false, 'manual');
    console.error(`\n[local] Automation disabled. ${HOTKEY_PREFIX_LABEL} o to re-enable.\n`);
    return;
  }

  if (command === 'p') {
    pauseAutomationTemporarily(AUTOMATION_COOLDOWN_MS, 'manual pause');
    return;
  }

  if (command === 'e') {
    recheckVisiblePrompt('manual hotkey');
    console.error(`\n[local] Rechecked visible prompt.\n`);
    return;
  }

  if (command === 'i') {
    printLocalStatus();
    return;
  }

  if (command === 's') {
    requestLauncherAction('switch');
    return;
  }

  if (command === 'r') {
    requestLauncherAction('restart');
    return;
  }

  if (command === 'c') {
    pauseAutomationTemporarily(MANUAL_OVERRIDE_MS, 'manual Ctrl-C', true);
    sendRaw('\x03', 'manual-ctrl-c');
    console.error(`\n[local] Sent Ctrl-C to Gemini and paused automation for ${Math.round(MANUAL_OVERRIDE_MS / 1000)}s.\n`);
    return;
  }

  if (command === 'q') {
    requestLauncherAction('exit');
    return;
  }

  console.error(`\n[local] Unknown command ${JSON.stringify(command)}. ${hotkeySummary()}\n`);
}

function noteManualInput() {
  clearContinueTimer();
  clearPromptCommandTimer();
  clearPendingSubmitTimers();
  clearInitialPromptTimer();
  clearInitialPromptSubmitConfirmTimer();
  clearAutomationResumeTimer();
  clearMenuPlan();
  pendingInitialPromptSubmit = null;
  pendingPromptCommand = null;
}

function manualInputSubmitsPrompt(bytes) {
  if (!Array.isArray(bytes)) return false;
  return bytes.includes(0x0d) || bytes.includes(0x0a);
}

function scheduleAutomationResumeRecheck() {
  clearAutomationResumeTimer();
  if (!automationEnabled || automationPausedUntil <= Date.now()) return;
  const delay = Math.max(10, automationPausedUntil - Date.now() + 20);
  automationResumeTimer = setTimeout(() => {
    automationResumeTimer = null;
    if (!isAutomationActive()) return;
    recheckVisiblePrompt('manual override ended');
  }, delay);
}

function bindResizeHandling() {
  if (resizeBound || !process.stdout.isTTY) return;
  resizeBound = true;
  process.stdout.on('resize', onTerminalResize);
}

function unbindResizeHandling() {
  if (!resizeBound || !process.stdout.isTTY) return;
  resizeBound = false;
  process.stdout.off('resize', onTerminalResize);
}

function onTerminalResize() {
  if (!activePty) return;
  try {
    activePty.resize(getTerminalColumns(), getTerminalRows());
  } catch {
    // ignore
  }
}

function getTerminalColumns() {
  return Math.max(1, process.stdout.columns || 120);
}

function getTerminalRows() {
  return Math.max(1, process.stdout.rows || 30);
}

function shouldArmContinueLoopForSubmittedText(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed) return false;
  if (/^\d+$/.test(trimmed)) return false;
  return true;
}

function sendChoice(text, reason, runId, options = {}) {
  if (runId !== activeRunId || !activePty) return false;
  try {
    if (DEBUG_AUTOMATION) {
      console.error(`[${FLAVOR_LABEL}][send] ${JSON.stringify(text)} (${reason})`);
    }
    if (text === '') {
      activePty.write('\r');
    } else if (shouldSubmitWithDelayedEnter(text, reason, options)) {
      const targetPty = activePty;
      if (shouldDelayWholeSlashSubmit(text, reason, options)) {
        scheduleDelayedSubmitText(runId, targetPty, text, reason, options);
      } else {
        activePty.write(text);
        scheduleSubmitEnter(runId, targetPty, reason, options);
      }
    } else {
      activePty.write(text + '\r');
      trackImmediateSlashCommandSubmit(text, reason, options);
    }
    if (options.armContinueLoop !== false && shouldArmContinueLoopForSubmittedText(text)) {
      continueLoopArmed = true;
    }
    return true;
  } catch (error) {
    console.error(`[warn] Failed to send automated input (${reason}): ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

function shouldDelayWholeSlashSubmit(text, reason = '', options = {}) {
  return shouldUseAutocompleteSafeSlashSubmit(text, reason, options);
}

function shouldUseAutocompleteSafeSlashSubmit(text, reason = '', options = {}) {
  const trimmed = String(text || '').trim();
  return trimmed.startsWith('/') && shouldTrackSlashCommandSubmit(reason, options);
}

function trackImmediateSlashCommandSubmit(text, reason = '', options = {}) {
  const trimmed = String(text || '').trim();
  if (!trimmed.startsWith('/')) return;
  if (!shouldTrackSlashCommandSubmit(reason, options)) return;
  pendingSubmitSettleUntil = Math.max(
    pendingSubmitSettleUntil,
    Date.now() + startupSlashHandoffDelayMs()
  );
}

function shouldTrackSlashCommandSubmit(reason = '', options = {}) {
  const commandKind = String(options.commandKind || '').trim();
  if ([
    'startup-clear',
    'startup-stats',
    'startup-model',
    'stats-session',
    'model-manage-open',
    'model-switch',
    'auth',
  ].includes(commandKind)) return true;

  const normalizedReason = String(reason || '').trim();
  return normalizedReason === 'startup clear'
    || normalizedReason === 'startup session stats capture'
    || normalizedReason === 'startup model capacity capture'
    || normalizedReason === 'auth'
    || normalizedReason === 'model-chain-exhausted-auth'
    || normalizedReason.startsWith('model-switch ');
}

function shouldSubmitWithDelayedEnter(text, reason = '', options = {}) {
  const delayMs = Number.isFinite(options.submitDelayMs)
    ? Number(options.submitDelayMs)
    : PROMPT_SUBMIT_DELAY_MS;
  if (delayMs <= 0) return false;

  const trimmed = String(text || '').trim();
  if (!trimmed) return false;
  if (/^\d+$/.test(trimmed)) return false;

  const normalizedReason = String(reason || '').trim();
  const commandKind = String(options.commandKind || '').trim();
  if (trimmed.startsWith('/')) {
    return [
      'startup-clear',
      'startup-stats',
      'startup-model',
      'stats-session',
      'model-manage-open',
      'model-switch',
      'auth',
    ].includes(commandKind)
      || normalizedReason === 'startup-clear'
      || normalizedReason === 'startup-stats'
      || normalizedReason === 'startup-model'
      || normalizedReason === 'startup clear'
      || normalizedReason === 'startup session stats capture'
      || normalizedReason === 'startup model capacity capture'
      || normalizedReason === 'auth'
      || normalizedReason === 'model-chain-exhausted-auth'
      || normalizedReason.startsWith('model-switch ');
  }

  const continueCommand = String(CONTINUE_COMMAND || '').trim();
  return normalizedReason === 'initial-prompt'
    || normalizedReason === 'continue'
    || normalizedReason === 'always-continue'
    || (continueCommand && trimmed === continueCommand);
}

function scheduleSubmitEnter(runId, targetPty, reason, options = {}) {
  const delayMs = Math.max(0, Number.isFinite(options.submitDelayMs)
    ? Number(options.submitDelayMs)
    : PROMPT_SUBMIT_DELAY_MS);
  const processingGraceMs = promptSubmitProcessingGraceForKind(options.commandKind, reason);
  pendingSubmitSettleUntil = Math.max(
    pendingSubmitSettleUntil,
    Date.now() + delayMs + PROMPT_SUBMIT_SETTLE_MS + processingGraceMs
  );
  const timer = setTimeout(() => {
    pendingSubmitTimers.delete(timer);
    if (runId !== activeRunId || !targetPty || !isAutomationActive()) return;
    try {
      markPendingPromptCommandSubmitted(options.commandKind);
      pendingSubmitSettleUntil = Math.max(
        pendingSubmitSettleUntil,
        Date.now() + PROMPT_SUBMIT_SETTLE_MS + processingGraceMs
      );
      targetPty.write('\r');
      pendingSubmitSettleUntil = Math.max(
        pendingSubmitSettleUntil,
        Date.now() + PROMPT_SUBMIT_SETTLE_MS + processingGraceMs
      );
    } catch (error) {
      console.error(`[warn] Failed to submit automated input (${reason}): ${error instanceof Error ? error.message : String(error)}`);
    }
  }, delayMs);
  pendingSubmitTimers.add(timer);
}

function scheduleDelayedSubmitText(runId, targetPty, text, reason, options = {}) {
  const delayMs = Math.max(0, Number.isFinite(options.submitDelayMs)
    ? Number(options.submitDelayMs)
    : PROMPT_SUBMIT_DELAY_MS);
  pendingSubmitSettleUntil = Math.max(
    pendingSubmitSettleUntil,
    Date.now() + delayMs + startupSlashHandoffDelayMs()
  );
  const timer = setTimeout(() => {
    pendingSubmitTimers.delete(timer);
    if (runId !== activeRunId || !targetPty || !isAutomationActive()) return;
    try {
      pendingSubmitSettleUntil = Math.max(
        pendingSubmitSettleUntil,
        Date.now() + startupSlashHandoffDelayMs()
      );
      if (shouldUseAutocompleteSafeSlashSubmit(text, reason, options)) {
        markPendingPromptCommandSubmitted(options.commandKind);
        targetPty.write(text);
        scheduleAutocompleteSafeSubmitEnter(runId, targetPty, reason, options);
      } else {
        markPendingPromptCommandSubmitted(options.commandKind);
        targetPty.write(`${text}\r`);
      }
      pendingSubmitSettleUntil = Math.max(
        pendingSubmitSettleUntil,
        Date.now() + startupSlashHandoffDelayMs()
      );
    } catch (error) {
      console.error(`[warn] Failed to submit automated input (${reason}): ${error instanceof Error ? error.message : String(error)}`);
    }
  }, delayMs);
  pendingSubmitTimers.add(timer);
}

function scheduleAutocompleteSafeSubmitEnter(runId, targetPty, reason, options = {}) {
  const dismissTimer = setTimeout(() => {
    pendingSubmitTimers.delete(dismissTimer);
    if (runId !== activeRunId || !targetPty || !isAutomationActive()) return;
    try {
      targetPty.write('\x1B');
      const enterTimer = setTimeout(() => {
        pendingSubmitTimers.delete(enterTimer);
        if (runId !== activeRunId || !targetPty || !isAutomationActive()) return;
        try {
          markPendingPromptCommandSubmitted(options.commandKind);
          targetPty.write('\r');
        } catch (error) {
          console.error(`[warn] Failed to submit Enter after autocomplete dismiss (${reason}): ${error instanceof Error ? error.message : String(error)}`);
        }
      }, 80);
      pendingSubmitTimers.add(enterTimer);
    } catch (error) {
      console.error(`[warn] Failed to dismiss autocomplete (${reason}): ${error instanceof Error ? error.message : String(error)}`);
    }
  }, 80);
  pendingSubmitTimers.add(dismissTimer);
}

function markPendingPromptCommandSubmitted(commandKind) {
  const submittedAt = Date.now();
  const kind = String(commandKind || '').trim();
  if (!kind || !pendingPromptCommand) return submittedAt;
  const pendingKind = String(pendingPromptCommand.kind || '').trim();
  const expectedFinalizeKind = `${kind}-finalize`;
  const matches =
    pendingKind === expectedFinalizeKind ||
    (kind === 'stats-session' && pendingKind === 'model-manage-open') ||
    (kind === 'model-manage-open' && pendingKind === 'model-manage-route') ||
    (kind === 'model-switch' && pendingKind === 'model-switch-finalize');
  if (matches) {
    const existingSubmittedAt = Number(pendingPromptCommand.submittedAt || 0);
    pendingPromptCommand.submittedAt = existingSubmittedAt > 0
      ? Math.min(existingSubmittedAt, submittedAt)
      : submittedAt;
  }
  return submittedAt;
}

function sendInitialPrompt(runId, detail, snapshot = currentSnapshot) {
  clearInitialPromptTimer();
  if (runId !== activeRunId || !activePty || sentInitialPrompt) return false;
  if (pendingPromptCommand) return false;
  if (String(snapshot?.promptInputText || '').trim()) return false;

  const promptText = (lastUserPrompt && lastUserPrompt !== String(GEMINI_INITIAL_PROMPT || '').trim())
    ? lastUserPrompt
    : GEMINI_INITIAL_PROMPT;
  const promptLabel = promptText === GEMINI_INITIAL_PROMPT ? 'initial prompt' : 'last user prompt';
  console.error(`\n[${FLAVOR_LABEL}] Auto-sending ${promptLabel} (${detail})...\n`);
  const sent = sendChoice(promptText, 'initial-prompt', runId);
  if (sent) {
    sentInitialPrompt = true;
    initialPromptPendingSince = 0;
    initialPromptSubmittedFingerprint = String(snapshot?.promptFingerprint || snapshot?.fingerprint || '').trim();
    pendingInitialPromptSubmit = {
      runId,
      text: promptText,
      attempts: 0,
      createdAt: Date.now(),
      promptFingerprint: initialPromptSubmittedFingerprint,
    };
    scheduleInitialPromptSubmitConfirmation(runId);
    if (!lastUserPrompt) lastUserPrompt = String(GEMINI_INITIAL_PROMPT || '').trim();
  }
  return sent;
}

function scheduleInitialPromptSubmitConfirmation(runId, delayMs = null) {
  clearInitialPromptSubmitConfirmTimer();
  if (!pendingInitialPromptSubmit || runId !== activeRunId || !activePty || shuttingDown) return;

  const effectiveDelayMs = Number.isFinite(delayMs)
    ? Math.max(30, Number(delayMs))
    : Math.max(80, Math.max(0, PROMPT_SUBMIT_DELAY_MS) + INITIAL_PROMPT_SUBMIT_CONFIRM_MS);

  if (DEBUG_AUTOMATION) {
    console.error(`[${FLAVOR_LABEL}][prompt] confirming initial prompt submit in ${effectiveDelayMs}ms`);
  }
  initialPromptSubmitConfirmTimer = setTimeout(() => {
    initialPromptSubmitConfirmTimer = null;
    confirmInitialPromptSubmitted(runId);
  }, effectiveDelayMs);
}

function confirmInitialPromptSubmitted(runId) {
  const submission = pendingInitialPromptSubmit;
  if (!submission || runId !== activeRunId || !activePty || shuttingDown) return;
  if (!isAutomationActive()) {
    scheduleInitialPromptSubmitConfirmation(runId, INITIAL_PROMPT_SUBMIT_CONFIRM_MS);
    return;
  }

  const snapshot = detectCurrentSnapshot();
  updateCurrentSnapshot(snapshot);
  const promptInputText = promptInputTextFromSnapshot(snapshot) || visibleSubmittedPromptInputText(submission.text);
  const quietForMs = Date.now() - lastTerminalDataAt;

  if (!promptInputText && snapshot?.kind === 'normal' && quietForMs < INITIAL_PROMPT_SETTLE_MS) {
    if (DEBUG_AUTOMATION) {
      console.error(`[${FLAVOR_LABEL}][prompt] initial prompt submit confirmation waiting for terminal to settle (${quietForMs}ms quiet)`);
    }
    scheduleInitialPromptSubmitConfirmation(runId, INITIAL_PROMPT_SUBMIT_CONFIRM_MS);
    return;
  }

  if (isInitialPromptSubmissionConfirmed(snapshot, submission)) {
    if (DEBUG_AUTOMATION) {
      console.error(`[${FLAVOR_LABEL}][prompt] initial prompt submit confirmed`);
    }
    pendingInitialPromptSubmit = null;
    return;
  }

  if (DEBUG_AUTOMATION) {
    console.error(`[${FLAVOR_LABEL}][prompt] initial prompt submit still pending; visible input=${JSON.stringify(promptInputText)}`);
  }
  if (!promptInputMatchesSubmittedPrompt(promptInputText, submission.text)) {
    pendingInitialPromptSubmit = null;
    return;
  }

  const maxAttempts = Math.max(1, INITIAL_PROMPT_SUBMIT_RETRY_MAX);
  if (submission.attempts < maxAttempts) {
    submission.attempts += 1;
    console.error(`\n[${FLAVOR_LABEL}] Initial prompt is still in the input field; retrying Enter (${submission.attempts}/${maxAttempts}).\n`);
    sendInitialPromptSubmitRetry(runId, submission.attempts);
    scheduleInitialPromptSubmitConfirmation(runId, INITIAL_PROMPT_SUBMIT_CONFIRM_MS);
    return;
  }

  console.error(`\n[${FLAVOR_LABEL}] Initial prompt stayed in the input field after ${maxAttempts} Enter retries; clearing and requeueing it.\n`);
  sendRaw('\x15', 'initial-prompt-clear-stuck-input');
  pendingInitialPromptSubmit = null;
  sentInitialPrompt = false;
  initialPromptSubmittedFingerprint = '';
  initialPromptPendingSince = 0;
  scheduleInitialPromptRetry(runId, 'retrying initial prompt after stuck input');
}

function isInitialPromptSubmissionConfirmed(snapshot, submission) {
  if (!submission) return true;
  const promptInputText = promptInputTextFromSnapshot(snapshot);
  if (!promptInputText) return true;
  if (snapshot?.kind !== 'normal') return true;
  return false;
}

function promptInputMatchesSubmittedPrompt(inputText, submittedText) {
  const input = normalizePromptInputForComparison(inputText);
  const submitted = normalizePromptInputForComparison(submittedText);
  if (!input || !submitted) return false;
  if (input === submitted || input.includes(submitted)) return true;
  return submitted.includes(input) && input.length >= Math.min(16, submitted.length);
}

function visibleSubmittedPromptInputText(submittedText) {
  const visibleInput = extractPromptInputText(String(currentScreenTerminalText() || '').split('\n'));
  if (promptInputMatchesSubmittedPrompt(visibleInput, submittedText)) return visibleInput;
  return '';
}

function normalizePromptInputForComparison(text) {
  return String(text || '')
    .replace(/\s+/g, ' ')
    .trim();
}

function sendInitialPromptSubmitRetry(runId, attempt) {
  if (runId !== activeRunId || !activePty || !isAutomationActive()) return false;
  try {
    if (attempt >= 2) {
      activePty.write('\x1B');
    }
    activePty.write('\r');
    return true;
  } catch (error) {
    console.error(`[warn] Failed to retry initial prompt Enter: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

function sendReplayPromptAfterSwitch(runId, detail) {
  if (runId !== activeRunId || !activePty) return false;
  const replayText = String(lastUserPrompt || GEMINI_INITIAL_PROMPT || '').trim();
  if (!replayText) return false;
  console.error(`\n[${FLAVOR_LABEL}] Replaying last user prompt after model switch (${detail})...\n`);
  return sendChoice(replayText, 'replay-after-switch', runId);
}

function shouldRetryInitialPromptAfterUsageLimit() {
  return Boolean(GEMINI_INITIAL_PROMPT && sentInitialPrompt);
}

function rearmInitialPromptAfterUsageLimitSwitch(targetModel = '') {
  if (!GEMINI_INITIAL_PROMPT) return false;

  sentInitialPrompt = false;
  initialPromptPendingSince = 0;
  initialPromptSubmittedFingerprint = '';
  continueLoopArmed = true;

  const target = String(targetModel || currentModel() || '').trim();
  const suffix = target ? ` on ${target}` : '';
  console.error(`\n[${FLAVOR_LABEL}] Usage-limit recovery: retrying initial prompt${suffix}.\n`);
  scheduleInitialPromptRetry(activeRunId, 'usage-limit model switch');
  return true;
}

function shouldAutoContinuePrompt(snapshot, options = {}) {
  const mode = effectiveAutoContinueMode(options);
  if (mode !== 'always') return false;
  if (Boolean(options.authHandoffInProgress ?? authHandoffInProgress)) return false;
  if (Boolean(options.authRestartTelemetryPending ?? authRestartTelemetryPending)) return false;
  if (snapshot?.kind !== 'normal' || !snapshot?.chatPromptActive) return false;
  if (promptInputTextFromSnapshot(snapshot)) return false;
  if (!Boolean(options.continueLoopArmed ?? continueLoopArmed)) return false;

  const promptFingerprint = String(snapshot?.promptFingerprint || '').trim();
  if (!promptFingerprint) return false;

  const submittedFingerprint = String(options.initialPromptSubmittedFingerprint ?? initialPromptSubmittedFingerprint ?? '').trim();
  if (submittedFingerprint && promptFingerprint === submittedFingerprint) return false;

  return true;
}

function selectedAutoContinueCommand(snapshot, options = {}) {
  const primary = String(options.continueCommand ?? CONTINUE_COMMAND ?? '').trim() || 'continue';
  const fallback = String(options.continueFallbackCommand ?? CONTINUE_FALLBACK_COMMAND ?? '').trim();
  if (shouldUseContinueFallbackPrompt(snapshot, options)) {
    return {
      text: fallback,
      reason: 'auto-continue recovery prompt',
      label: fallback,
      usingFallback: true,
    };
  }
  return {
    text: primary,
    reason: 'auto-continue prompt',
    label: primary,
    usingFallback: false,
  };
}

function shouldUseContinueFallbackPrompt(snapshot, options = {}) {
  const fallback = String(options.continueFallbackCommand ?? CONTINUE_FALLBACK_COMMAND ?? '').trim();
  const primary = String(options.continueCommand ?? CONTINUE_COMMAND ?? '').trim() || 'continue';
  if (!fallback || fallback === primary) return false;
  if (snapshot?.kind !== 'normal' || !snapshot?.chatPromptActive) return false;
  const text = String(options.visibleText ?? (normalizedTail || currentScreenTerminalText()) ?? '').trim();
  return hasRepeatedConcludedSessionText(text, options);
}

function hasRepeatedConcludedSessionText(text, options = {}) {
  const repeatThreshold = Math.max(2, toNumber(options.concludedSessionRepeatThreshold, 2));
  return concludedSessionKeywordBlockCount(text) >= repeatThreshold;
}

function concludedSessionKeywordBlockCount(text) {
  return concludedSessionCandidateBlocks(text).filter(hasConcludedSessionText).length;
}

function concludedSessionCandidateBlocks(text) {
  const normalized = normalizeTerminalText(String(text || ''));
  if (!normalized) return [];
  const blocks = [];
  let current = [];

  const flush = () => {
    const block = current.join('\n').replace(/\s+/g, ' ').trim();
    current = [];
    if (block) blocks.push(block);
  };

  for (const rawLine of normalized.split('\n')) {
    const line = String(rawLine || '').trim();
    if (!line) {
      if (current.length) current.push('');
      continue;
    }
    if (isGeminiUserPromptLine(line) || isGeminiScreenSeparatorLine(line)) {
      flush();
      continue;
    }
    if (/^✦\s+/.test(line)) {
      flush();
    }
    current.push(line);
  }
  flush();

  return blocks.filter((block) => block.length >= 24);
}

function isGeminiUserPromptLine(line) {
  return /^>\s+\S/.test(String(line || '').trim());
}

function isGeminiScreenSeparatorLine(line) {
  return /^[▄▀─━═]{8,}$/.test(String(line || '').trim());
}

function hasConcludedSessionText(text) {
  const families = concludedSessionKeywordFamilies(text);
  return families.includes('context') &&
    families.includes('completion') &&
    families.includes('idle');
}

function concludedSessionKeywordFamilies(text) {
  const normalized = String(text || '').replace(/\s+/g, ' ').toLowerCase();
  if (!normalized) return [];

  const families = new Set();
  if (/\b(?:session|task|tasks|request|requested|instructions?|work|refactor(?:ing)?|lint(?:ing)?|development)\b/.test(normalized)) {
    families.add('context');
  }
  if (/\b(?:conclud(?:e|ed|es|ing)|conclusion|complete(?:d|ly)?|finish(?:ed|ing)?|done|implemented|verified|success(?:ful|fully)?)\b/.test(normalized)) {
    families.add('completion');
  }
  if (/\b(?:idle|standby|standing\s+by|await(?:ing)?|pending|terminat(?:e|ed|ing))\b/.test(normalized) ||
      /\bno\s+(?:further|additional|more)\b/.test(normalized) ||
      /\bnothing\s+(?:else|more|further)\b/.test(normalized) ||
      /\bnew\s+(?:session|task|request)\b/.test(normalized) ||
      /\bstart\s+(?:a\s+)?new\b/.test(normalized)) {
    families.add('idle');
  }
  return [...families];
}

function effectiveAutoContinueMode(options = {}) {
  const mode = String(options.autoContinueMode ?? AUTO_CONTINUE_MODE ?? '').trim();
  if (Boolean(options.promptAutoContinueAlways ?? promptAutoContinueAlways)) return 'always';
  return mode;
}

function shouldLaunchInitialPromptWithLaunchArgs(capabilities = currentGeminiCliCapabilities, options = {}) {
  if (!GEMINI_INITIAL_PROMPT) return false;
  if (options.ptyAvailable === false) return true;
  if (shouldRequireStartupStatsBeforeInitialPrompt()) return false;
  return capabilities?.startupStatsAutomationSupported === false;
}

function shouldRequireStartupStatsBeforeInitialPrompt() {
  return Boolean(GEMINI_INITIAL_PROMPT);
}

function shouldDelayInitialPromptForStartupStats(options = {}) {
  const hasInitialPrompt = options.hasInitialPrompt ?? shouldRequireStartupStatsBeforeInitialPrompt();
  if (!hasInitialPrompt) return false;

  const effectivePendingPromptCommand = Object.prototype.hasOwnProperty.call(options, 'pendingPromptCommand')
    ? options.pendingPromptCommand
    : pendingPromptCommand;
  const blocksInitialPrompt = Boolean(options.startupStatsBlocksInitialPrompt ?? startupStatsBlocksInitialPrompt);
  if (blocksInitialPrompt) return true;

  const blockedReason = String(options.startupStatsBlockedReason ?? startupStatsBlockedReason ?? '').trim();
  if (blockedReason) return isStartupPromptCommandKind(effectivePendingPromptCommand?.kind);
  if (buildNextStartupCommand(options)) return true;

  if (Boolean(options.startupStatsObserved ?? startupStatsObserved)) return false;

  return isStartupPromptCommandKind(effectivePendingPromptCommand?.kind);
}

function isStartupPromptCommandKind(kind) {
  return String(kind || '').trim().startsWith('startup-');
}

function resolveStartupStatsBlockReason(options = {}) {
  const hasInitialPrompt = options.hasInitialPrompt ?? shouldRequireStartupStatsBeforeInitialPrompt();
  if (!hasInitialPrompt) return '';

  const capabilities = options.capabilities ?? currentGeminiCliCapabilities;
  const disabledReason = String(capabilities?.startupStatsAutomationDisabledReason || '').trim();
  if (disabledReason) return disabledReason;

  if (options.ptyAvailable === false) {
    return `PTY backend unavailable, so ${startupPipelineLabel()} cannot be automated before prompt injection`;
  }

  return '';
}

function buildStartupCommandPipeline(capabilities = currentGeminiCliCapabilities) {
  return delayStartupFirstCommand(buildNextStartupCommand({
    capabilities,
    startupClearCompleted: false,
    startupStatsObserved: false,
    startupModelCapacityObserved: false,
    startupStatsBlockedReason: '',
  }));
}

function delayStartupFirstCommand(command) {
  if (!command) return null;
  return {
    ...command,
    notBeforeAt: Math.max(Number(command.notBeforeAt || 0), Date.now() + Math.max(0, STARTUP_FIRST_COMMAND_DELAY_MS)),
  };
}

function buildPostAuthTelemetryCommand(capabilities = currentGeminiCliCapabilities) {
  startupClearCompleted = true;
  startupStatsObserved = false;
  startupStatsSnapshot = null;
  startupStatsBlockedReason = '';
  startupStatsBlocksInitialPrompt = false;
  startupModelCapacityObserved = false;
  startupModelCapacitySnapshot = null;

  return buildNextStartupCommand({
    capabilities,
    startupClearCompleted: true,
    startupStatsObserved: false,
    startupModelCapacityObserved: false,
    startupStatsBlockedReason: '',
    startupStatsBlocksInitialPrompt: false,
  });
}

function buildNextStartupCommand(options = {}) {
  const blockedReason = String(options.startupStatsBlockedReason ?? startupStatsBlockedReason ?? '').trim();
  const blocksInitialPrompt = Boolean(options.startupStatsBlocksInitialPrompt ?? startupStatsBlocksInitialPrompt);
  if (blockedReason && blocksInitialPrompt) return null;
  if (isStartupModelUnavailableReason(blockedReason)) return null;

  const statsObserved = Boolean(options.startupStatsObserved ?? startupStatsObserved);
  const clearCompleted = Boolean(options.startupClearCompleted ?? startupClearCompleted);
  const modelCapacityObserved = Boolean(options.startupModelCapacityObserved ?? startupModelCapacityObserved);
  const capabilities = options.capabilities ?? currentGeminiCliCapabilities;

  if (!clearCompleted) {
    const startupClearCommand = buildStartupClearCommand();
    if (startupClearCommand) return startupClearCommand;
  }

  if (!statsObserved && !blockedReason) {
    const startupStatsCommand = buildStartupStatsCommand(capabilities);
    if (startupStatsCommand) return startupStatsCommand;
  }

  if (!modelCapacityObserved) {
    return buildStartupModelCommand();
  }

  return null;
}

function isStartupModelUnavailableReason(reason) {
  const text = String(reason || '').trim();
  if (!text) return false;
  const command = String(STARTUP_MODEL_COMMAND || '').trim();
  if (command && text.includes(`startup ${command}`)) return true;
  return /startup\s+\/model\b/i.test(text);
}

function shouldRequeueStartupCommand(snapshot, options = {}) {
  const effectivePendingPromptCommand = Object.prototype.hasOwnProperty.call(options, 'pendingPromptCommand')
    ? options.pendingPromptCommand
    : pendingPromptCommand;
  if (effectivePendingPromptCommand) return false;
  if ((options.sentInitialPrompt ?? sentInitialPrompt)) return false;
  const blockedReason = String(options.startupStatsBlockedReason ?? startupStatsBlockedReason ?? '').trim();
  const blocksInitialPrompt = Boolean(options.startupStatsBlocksInitialPrompt ?? startupStatsBlocksInitialPrompt);
  if (blockedReason && blocksInitialPrompt) return false;
  if (Boolean(options.authWaiting ?? (authWaitSince > 0))) return false;
  if (snapshot?.kind !== 'normal') return false;
  return Boolean(buildNextStartupCommand(options));
}

function buildStartupClearCommand() {
  const text = String(STARTUP_CLEAR_COMMAND || '').trim();
  if (!text) return null;

  return {
    kind: 'startup-clear',
    text,
    reason: 'startup clear',
    label: text,
    createdAt: Date.now(),
  };
}

function buildStartupStatsCommand(capabilities = currentGeminiCliCapabilities) {
  if (capabilities?.startupStatsAutomationSupported === false) return null;
  const text = String(STARTUP_STATS_COMMAND || '').trim();
  if (!text) return null;

  return {
    kind: 'startup-stats',
    text,
    reason: 'startup session stats capture',
    label: text,
    fallbackText: resolveStatsSessionFallbackCommand(text),
    fallbackUsed: false,
    createdAt: Date.now(),
  };
}

function buildStartupModelCommand() {
  const text = String(STARTUP_MODEL_COMMAND || '').trim();
  if (!text) return null;

  return {
    kind: 'startup-model',
    text,
    reason: 'startup model capacity capture',
    label: text,
    createdAt: Date.now(),
  };
}

function buildModelChainExhaustedAuthCommand(reason = '') {
  const text = String(AUTH_COMMAND || '').trim();
  if (!text) return null;

  return {
    kind: 'auth',
    text,
    reason: 'model-chain-exhausted-auth',
    label: text,
    detail: String(reason || '').trim(),
    createdAt: Date.now(),
  };
}

function buildStartupStatsFallbackCommand(command = {}) {
  if (command?.fallbackUsed === true) return null;

  const text = resolveStatsSessionFallbackCommand(command?.text || STATS_SESSION_COMMAND);
  if (!text) return null;

  return {
    kind: 'startup-stats',
    text,
    reason: 'startup session stats capture fallback',
    label: text,
    fallbackText: '',
    fallbackUsed: true,
    createdAt: Date.now(),
  };
}

function buildModelManageStarterCommand(targetIndex, targetModel, capabilities = currentGeminiCliCapabilities, options = {}) {
  const index = Number(targetIndex);
  const model = String(targetModel || '').trim();
  if (!Number.isInteger(index) || index < 0 || !model) return null;

  if (capabilities?.statsSessionAutomationSupported === false) {
    return {
      kind: 'model-manage-open',
      text: MODEL_MANAGE_COMMAND,
      reason: `open model manage for ${model}`,
      label: MODEL_MANAGE_COMMAND,
      targetIndex: index,
      targetModel: model,
      advanceReason: options.advanceReason || '',
      retryInitialPromptAfterSwitch: options.retryInitialPromptAfterSwitch === true,
      createdAt: Date.now(),
    };
  }

  return {
    kind: 'stats-session',
    text: STATS_SESSION_COMMAND,
    reason: 'stats-session before model-manage',
    label: STATS_SESSION_COMMAND,
    targetIndex: index,
    targetModel: model,
    advanceReason: options.advanceReason || '',
    retryInitialPromptAfterSwitch: options.retryInitialPromptAfterSwitch === true,
    createdAt: Date.now(),
  };
}

function scheduleInitialPromptRetry(runId, reason = 'initial prompt retry') {
  if (!GEMINI_INITIAL_PROMPT || sentInitialPrompt || initialPromptTimer || !activePty || !isAutomationActive()) return;

  initialPromptTimer = setTimeout(() => {
    initialPromptTimer = null;
    if (runId !== activeRunId || sentInitialPrompt || !activePty || !isAutomationActive()) return;
    recheckVisiblePrompt(reason);
  }, INITIAL_PROMPT_RETRY_MS);
}

function dismissCapacityPopup(reason = 'capacity-dismiss') {
  if (!activePty) return false;
  return sendRaw('\x1B', reason);
}

const SPINNER_CANCEL_GAP_MS = 1500;
const SPINNER_CANCEL_MAX_ATTEMPTS = 3;
function nudgeSpinnerForPendingModelSwitch() {
  if (!activePty || !pendingPromptCommand || pendingPromptCommand.kind !== 'model-switch') return 'noop';
  const now = Date.now();
  const attempts = Number(pendingPromptCommand.spinnerCancelAttempts || 0);
  const lastSentAt = Number(pendingPromptCommand.spinnerCancelSentAt || 0);
  if (lastSentAt && now - lastSentAt < SPINNER_CANCEL_GAP_MS) return 'waiting';
  if (attempts >= SPINNER_CANCEL_MAX_ATTEMPTS) return 'exhausted';
  pendingPromptCommand.spinnerCancelAttempts = attempts + 1;
  pendingPromptCommand.spinnerCancelSentAt = now;
  console.error(`\n[${FLAVOR_LABEL}] Cancelling Gemini CLI thinking spinner before sending model-switch (attempt ${attempts + 1}/${SPINNER_CANCEL_MAX_ATTEMPTS}).\n`);
  sendRaw('\x1B', `model-switch-cancel-spinner-${attempts + 1}`);
  return 'sent';
}

function sendRaw(text, reason = 'raw') {
  if (!activePty) return false;
  try {
    if (DEBUG_AUTOMATION) {
      console.error(`[${FLAVOR_LABEL}][raw] ${JSON.stringify(text)} (${reason})`);
    }
    activePty.write(text);
    return true;
  } catch (error) {
    console.error(`[warn] Failed to send raw input (${reason}): ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

function extractStartupStatsSnapshot(text) {
  const lines = normalizedSessionStatsLines(text);
  if (lines.length === 0) return null;

  for (let index = 0; index < lines.length; index += 1) {
    if (!/session stats/i.test(lines[index])) continue;
    const candidate = parseStartupStatsCandidate(lines.slice(index, index + 40));
    if (candidate) return candidate;
  }

  return null;
}

function extractStartupModelCapacitySnapshot(text) {
  const lines = normalizedSessionStatsLines(text);
  if (lines.length === 0) return null;

  let startIndex = -1;
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    if (/^select model$/i.test(lines[index]) || /^\/model$/i.test(lines[index])) {
      startIndex = index;
      break;
    }
  }
  if (startIndex < 0) {
    for (let index = lines.length - 1; index >= 0; index -= 1) {
      if (/^model usage$/i.test(lines[index])) {
        startIndex = index;
        break;
      }
    }
  }
  if (startIndex < 0) return null;

  const candidateLines = [];
  let currentModel = '';
  let sawModelDialog = false;
  let sawModelUsage = false;

  for (const line of lines.slice(startIndex, startIndex + 80)) {
    if (/type your message/i.test(line)) break;
    const lower = line.toLowerCase();
    if (lower === 'select model' || lower === '/model') {
      sawModelDialog = true;
    }
    if (lower === 'model usage') {
      sawModelUsage = true;
    }
    const selectedModel = parseSelectedModelLine(line);
    if (selectedModel) currentModel = selectedModel;
    candidateLines.push(line);
  }

  const rows = candidateLines
    .map((line) => parseStartupModelCapacityRow(line))
    .filter(Boolean);

  if (!sawModelDialog && rows.length === 0) return null;
  if (!sawModelUsage && rows.length === 0 && !currentModel) return null;

  return {
    startupModelCommand: STARTUP_MODEL_COMMAND,
    startupModelCommandSource: 'runner_banner',
    currentModel,
    rows,
    rawLines: candidateLines,
  };
}

function resolveDirectModelSwitchConfirmation(targetModel, options = {}) {
  const observedModel = extractVisibleCurrentModel(options.screenText)
    || extractVisibleCurrentModel(options.visibleText);
  return {
    confirmed: modelIdentifiersMatch(observedModel, targetModel),
    observedModel,
  };
}

function isDirectModelSwitchConfirmed(targetModel, options = {}) {
  return resolveDirectModelSwitchConfirmation(targetModel, options).confirmed;
}

function extractVisibleCurrentModel(text) {
  const statusRowModel = extractVisibleStatusRowCurrentModel(text);
  if (statusRowModel) return statusRowModel;

  const modelPanelSnapshot = extractStartupModelCapacitySnapshot(text);
  return String(modelPanelSnapshot?.currentModel || '').trim();
}

function extractVisibleStatusRowCurrentModel(text) {
  const lines = normalizedSessionStatsLines(text);
  if (lines.length === 0) return '';

  for (let index = lines.length - 1; index >= 0; index -= 1) {
    const header = lines[index];
    const lowerHeader = header.toLowerCase();
    if (!lowerHeader.includes('/model')) continue;
    if (!/\b(workspace|branch|sandbox)\b/i.test(header)) continue;

    const candidates = lines.slice(index + 1, index + 5);
    for (const candidate of candidates) {
      const model = extractGeminiModelIdentifier(candidate);
      if (model) return model;
    }
  }

  return '';
}

function modelIdentifiersMatch(left, right) {
  const normalizedLeft = normalizeModelIdentifier(left);
  const normalizedRight = normalizeModelIdentifier(right);
  return Boolean(normalizedLeft && normalizedRight && normalizedLeft === normalizedRight);
}

function findModelIndexByIdentifier(model, models = MODELS) {
  const chain = Array.isArray(models) ? models : [];
  for (let index = 0; index < chain.length; index += 1) {
    if (modelIdentifiersMatch(chain[index], model)) return index;
  }
  return -1;
}

function resolveModelIndexFromVisibleCurrentModel(models, currentIndex, text) {
  const visibleModel = extractVisibleCurrentModel(text);
  const visibleIndex = findModelIndexByIdentifier(visibleModel, models);
  if (visibleIndex < 0) {
    return {
      modelIndex: Number.isInteger(currentIndex) ? currentIndex : 0,
      visibleModel,
      visibleIndex: -1,
      changed: false,
    };
  }

  const normalizedCurrentIndex = Number.isInteger(currentIndex) ? currentIndex : 0;
  return {
    modelIndex: visibleIndex,
    visibleModel,
    visibleIndex,
    changed: visibleIndex !== normalizedCurrentIndex,
  };
}

function applyVisibleModelReconcileOptions(resolution, currentIndex, options = {}) {
  const normalizedCurrentIndex = Number.isInteger(currentIndex) ? currentIndex : 0;
  if (
    resolution.visibleIndex >= 0
    && options.allowBackward === false
    && resolution.visibleIndex < normalizedCurrentIndex
  ) {
    return {
      ...resolution,
      modelIndex: normalizedCurrentIndex,
      changed: false,
      ignored: true,
      ignoredReason: 'visible model is behind current runner model',
    };
  }

  return resolution;
}

function resolveModelIndexFromVisibleTerminalTexts(models, currentIndex, screenText, visibleText, options = {}) {
  const screenResolution = resolveModelIndexFromVisibleCurrentModel(models, currentIndex, screenText);
  if (screenResolution.visibleIndex >= 0) {
    return applyVisibleModelReconcileOptions(screenResolution, currentIndex, options);
  }
  const visibleResolution = resolveModelIndexFromVisibleCurrentModel(models, currentIndex, visibleText);
  return applyVisibleModelReconcileOptions(visibleResolution, currentIndex, options);
}

function reconcileModelIndexFromVisibleTerminal(reason, options = {}) {
  const resolution = resolveModelIndexFromVisibleTerminalTexts(
    MODELS,
    modelIndex,
    currentScreenTerminalText(),
    currentVisibleTerminalText(),
    options
  );
  if (resolution.ignored) return false;
  if (!resolution.changed || resolution.visibleIndex < 0) return false;

  const previousModel = currentModel();
  modelIndex = resolution.visibleIndex;
  console.error(`\n[${FLAVOR_LABEL}] Visible model is ${resolution.visibleModel}; correcting runner model state from ${previousModel} before ${reason}.\n`);
  return true;
}

function normalizeModelIdentifier(value) {
  const extracted = extractGeminiModelIdentifier(value);
  const raw = extracted || String(value || '').trim();
  return raw.toLowerCase();
}

function extractGeminiModelIdentifier(value) {
  const match = String(value || '').match(/\bgemini[-\w.]*[a-z0-9]\b/i);
  return match ? match[0].trim() : '';
}

function parseSelectedModelLine(line) {
  const raw = String(line || '');
  const numberedOption = /^\s*(?:[●◉○◌]\s*)?\d+\./u.test(raw);
  const selectedOption = /[●◉]/u.test(raw) || /^\s*[>▸]/u.test(raw);
  const normalized = raw
    .replace(/[●◉○◌]/g, ' ')
    .replace(/^\s*(?:[>▸]\s*)?(?:\d+\.\s*)?/, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!normalized) return '';
  if (/\b\d{1,3}%/.test(normalized)) return '';

  const manualMatch = normalized.match(/^manual\s*\(([^)]+)\)/i);
  if (manualMatch) return (!numberedOption || selectedOption) ? manualMatch[1].trim() : '';
  if (/^(auto|manual)$/i.test(normalized)) return '';
  if (/^gemini[-\w.]+/i.test(normalized)) {
    return (!numberedOption || selectedOption) ? normalized.split(/\s+/)[0] : '';
  }
  return '';
}

function parseStartupModelCapacityRow(line) {
  const trimmed = String(line || '').replace(/\s+/g, ' ').trim();
  if (!trimmed || /^(model usage|select model|remember model|press esc|to use a specific|usage limits span|please \/auth)/i.test(trimmed)) {
    return null;
  }

  const percentMatch = trimmed.match(/^(.*?)\s+(?:[▬▰█#=\-]+\s+)?(\d{1,3})%\s*(?:used)?(?:\s*\(?\s*(?:limit\s+)?resets?\s*(?:in|:)?\s*([^)]+?)\s*\)?)?$/i);
  if (!percentMatch) return null;

  const model = percentMatch[1]
    .replace(/\s*[▬▰█#=\-]+\s*$/u, '')
    .replace(/[●◉○◌]/g, ' ')
    .replace(/^\s*(?:[>▸]\s*)?(?:\d+\.\s*)?/, '')
    .trim();
  if (!model || /^[-▬▰█#=]+$/.test(model)) return null;

  const usedPercentage = Math.max(0, Math.min(100, Number.parseInt(percentMatch[2], 10)));
  const resetTime = String(percentMatch[3] || '').trim();
  return {
    model,
    usedPercentage,
    resetTime,
    rawText: trimmed,
  };
}

function normalizedSessionStatsLines(text) {
  return normalizedSessionStatsParsingText(text)
    .split('\n')
    .map((line) => cleanSessionStatsLine(line))
    .filter(Boolean);
}

function normalizedSessionStatsParsingText(text) {
  return String(text || '')
    .replace(/\u001B\][^\u0007\u001B]*(?:\u0007|\u001B\\)/g, '')
    .replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/\u001B/g, '')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(/\u0000/g, '')
    .replace(/[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ' ');
}

function cleanSessionStatsLine(line) {
  const trimmed = String(line || '').trim();
  if (!trimmed) return '';
  if (/^[╭╮╰╯│║┃─━═▀▄▁▂▃▅▆▇█]+$/u.test(trimmed)) return '';

  const withoutBorders = trimmed
    .replace(/^[│║┃\s]+/u, '')
    .replace(/[│║┃\s]+$/u, '')
    .trim();

  if (/^[╭╮╰╯│║┃─━═▀▄▁▂▃▅▆▇█]+$/u.test(withoutBorders)) return '';
  return withoutBorders;
}

function parseStartupStatsCandidate(lines) {
  let sessionID = '';
  let authMethod = '';
  let tier = '';
  let toolCalls = '';
  let wallTime = '';
  let sawModelUsage = false;
  let currentUsageModel = '';
  const modelUsage = [];

  for (const line of lines) {
    if (/type your message/i.test(line)) break;

    const lower = line.toLowerCase();
    if (lower === 'session stats' || lower === 'interaction summary' || lower === 'performance' || lower === 'model usage') {
      if (lower === 'model usage') sawModelUsage = true;
      continue;
    }
    if (lower.includes('use /model to view model quota information')) {
      sawModelUsage = true;
      continue;
    }

    const pair = parseStartupStatsKeyValue(line);
    if (pair) {
      switch (pair.key) {
        case 'session id':
          sessionID = pair.value;
          break;
        case 'auth method':
          authMethod = pair.value;
          break;
        case 'tier':
          tier = pair.value;
          break;
        case 'tool calls':
          toolCalls = pair.value;
          break;
        case 'wall time':
          wallTime = pair.value;
          break;
        default:
          break;
      }
      continue;
    }

    if (!sawModelUsage) continue;
    const parsedRow = parseStartupStatsUsageRow(line, currentUsageModel);
    if (!parsedRow) continue;
    currentUsageModel = parsedRow.currentModel;
    modelUsage.push(parsedRow.row);
  }

  if (!sessionID || !authMethod || !tier || !toolCalls || !wallTime) {
    return null;
  }

  return {
    sessionID,
    authMethod,
    tier,
    toolCalls,
    wallTime,
    modelUsage,
  };
}

function parseStartupStatsKeyValue(line) {
  const separatorIndex = String(line || '').indexOf(':');
  if (separatorIndex < 0) return null;

  const key = String(line.slice(0, separatorIndex))
    .replace(/»/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
  const value = String(line.slice(separatorIndex + 1)).trim();
  if (!key || !value) return null;
  return { key, value };
}

function parseStartupStatsUsageRow(line, currentModel) {
  const trimmed = String(line || '').trim();
  if (!trimmed) return null;
  if (/input tokens/i.test(trimmed)) return null;
  if (/^[─━═-]+$/u.test(trimmed)) return null;

  const tokens = trimmed.split(/\s+/).filter(Boolean);
  if (tokens.length < 5) return null;

  const numericTokens = tokens.slice(-4);
  const parsedNumbers = numericTokens.map((token) => {
    const normalized = token.replace(/,/g, '');
    return /^\d+$/.test(normalized) ? Number(normalized) : null;
  });
  if (parsedNumbers.some((value) => !Number.isInteger(value))) return null;

  const name = tokens.slice(0, -4).join(' ').trim();
  if (!name) return null;

  if (name.startsWith('↳')) {
    if (!currentModel) return null;
    const label = name.replace(/^↳\s*/u, '').trim() || null;
    return {
      row: {
        model: currentModel,
        label,
        requests: parsedNumbers[0],
        inputTokens: parsedNumbers[1],
        cacheReads: parsedNumbers[2],
        outputTokens: parsedNumbers[3],
      },
      currentModel,
    };
  }

  return {
    row: {
      model: name,
      label: null,
      requests: parsedNumbers[0],
      inputTokens: parsedNumbers[1],
      cacheReads: parsedNumbers[2],
      outputTokens: parsedNumbers[3],
    },
    currentModel: name,
  };
}

function requestLauncherAction(kind, code = 0) {
  if (plannedAction?.kind === 'finish') return;
  if (plannedAction?.kind === kind && plannedAction?.code === code) return;

  clearAllTimers();
  clearMenuPlan();
  pendingPromptCommand = null;
  switching = false;
  plannedAction = { kind, code };

  if (!activePty && !activeChild) {
    fulfillPlannedAction();
    return;
  }

  const label = kind === 'switch'
    ? 'Switching model'
    : kind === 'restart'
      ? 'Restarting current model'
      : kind === 'finish'
        ? 'Finishing session'
        : 'Quitting launcher';

  console.error(`\n[local] ${label}...\n`);
  if (activePty) {
    sendRaw('\x03', `local-${kind}`);
  } else if (activeChild) {
    activeChild.kill('SIGINT');
  }
  forceKillTimer = setTimeout(() => {
    if (!plannedAction || plannedAction.kind !== kind) return;
    try {
      activePty?.kill();
      activeChild?.kill('SIGKILL');
    } catch {
      // ignore
    }
  }, FORCE_KILL_AFTER_MS);
}

function fulfillPlannedAction() {
  if (!plannedAction) return;
  const action = plannedAction;
  plannedAction = null;

  if (action.kind === 'switch') {
    const nextIndex = findNextEligibleModelIndex(modelIndex);
    if (nextIndex < 0) {
      finishSessionAfterModelChainExhaustion();
      return;
    }
    modelIndex = nextIndex;
    spawnGemini();
    return;
  }
  if (action.kind === 'restart') {
    spawnGemini();
    return;
  }
  if (action.kind === 'finish') {
    cleanupAndExit(action.code ?? SESSION_COMPLETE_HOLD_OPEN_EXIT_CODE);
    return;
  }
  cleanupAndExit(action.code ?? 0);
}

function setAutomationEnabled(enabled, reason = 'manual') {
  automationEnabled = enabled;
  automationDisabledReason = enabled ? '' : reason;

  if (!enabled) {
    automationPausedUntil = 0;
    promptAutoContinueAlways = false;
    pendingPromptCommand = null;
    clearAllTimers();
    clearMenuPlan();
    recentActionKeys.clear();
    return;
  }

  automationPausedUntil = 0;
  if (shouldForceAlwaysAutoContinueOnAutomationEnable(reason)) {
    promptAutoContinueAlways = true;
    continueLoopArmed = true;
  }
  recentActionKeys.clear();
  clearAllTimers();
  clearMenuPlan();
  recheckVisiblePrompt('automation enabled');
}

function shouldForceAlwaysAutoContinueOnAutomationEnable(reason = 'manual') {
  return String(reason || 'manual').trim() === 'manual';
}

function pauseAutomationTemporarily(ms, reason, silent = false) {
  if (!automationEnabled) return;
  clearContinueTimer();
  clearPromptCommandTimer();
  clearMenuPlan();
  automationPausedUntil = Math.max(automationPausedUntil, Date.now() + ms);
  scheduleAutomationResumeRecheck();
  if (!silent) {
    console.error(`\n[${FLAVOR_LABEL}] Automation paused for ${Math.round(ms / 1000)}s (${reason}). ${hotkeySummary()}\n`);
  }
}

function isAutomationActive() {
  return automationEnabled && Date.now() >= automationPausedUntil && !shuttingDown && Boolean(activePty);
}

function recheckVisiblePrompt(reason = 'manual recheck') {
  if (!activePty || shuttingDown || !isAutomationActive()) return;
  if (DEBUG_AUTOMATION) {
    console.error(`[${FLAVOR_LABEL}][auto] Rechecking visible prompt (${reason})`);
  }
  const snapshot = detectCurrentSnapshot();
  updateCurrentSnapshot(snapshot);
  maybeAutomate(activeRunId, snapshot);
}

function scheduleStaticRecheck(delay = STATIC_RECHECK_MS) {
  clearStaticRecheckTimer();
  if (!activePty || shuttingDown || !isAutomationActive()) return;
  const initialPromptStillPending = Boolean(GEMINI_INITIAL_PROMPT && !sentInitialPrompt);
  if (currentSnapshot.kind === 'normal' && !pendingPromptCommand && !initialPromptStillPending) return;
  if (currentSnapshot.kind === 'usage_limit' && !pendingPromptCommand) return;

  staticRecheckTimer = setTimeout(() => {
    staticRecheckTimer = null;
    if (!activePty || shuttingDown || !isAutomationActive()) return;
    recheckVisiblePrompt('static prompt heartbeat');
  }, Math.max(30, delay));
}

function hotkeySummary() {
  return `${HOTKEY_PREFIX_LABEL} h help | ${HOTKEY_PREFIX_LABEL} a auto toggle | ${HOTKEY_PREFIX_LABEL} o automation on | ${HOTKEY_PREFIX_LABEL} x automation off | ${HOTKEY_PREFIX_LABEL} p pause auto | ${HOTKEY_PREFIX_LABEL} e recheck | ${HOTKEY_PREFIX_LABEL} i status | ${HOTKEY_PREFIX_LABEL} s switch | ${HOTKEY_PREFIX_LABEL} r restart | ${HOTKEY_PREFIX_LABEL} c Ctrl-C | ${HOTKEY_PREFIX_LABEL} q quit`;
}

function printLocalHelp() {
  console.error(
    [
      '',
      `[local] ${hotkeySummary()}`,
      `[local] Press the prefix first, then the command key.`,
      `[local] Manual typing cancels pending automated keystrokes without disabling automation.`,
      `[local] Current model: ${currentModel()}`,
      '',
    ].join('\n')
  );
}

function printLocalStatus() {
  const pausedForMs = Math.max(0, automationPausedUntil - Date.now());
  const selection = currentSnapshot.options.find((option) => option.selected)?.label || '(none)';
  const screenSummary = screenModel?.renderText(16)?.split('\n').slice(-4).join(' | ') || '(empty)';
  console.error(
    [
      '',
      `[local] Model: ${currentModel()}`,
      `[local] Automation: ${automationEnabled ? 'enabled' : `disabled (${automationDisabledReason || 'manual'})`}`,
      `[local] Auto-continue: ${effectiveAutoContinueMode()}`,
      `[local] Paused: ${pausedForMs > 0 ? `${Math.ceil(pausedForMs / 1000)}s remaining` : 'no'}`,
      `[local] Snapshot: ${currentSnapshot.kind}/${currentSnapshot.source}`,
      `[local] Fingerprint: ${currentSnapshot.fingerprint}`,
      `[local] Selected option: ${selection}`,
      `[local] Visible tail: ${screenSummary}`,
      '',
    ].join('\n')
  );
}

function bindProcessCleanup() {
  process.on('SIGINT', () => cleanupAndExit(130));
  process.on('SIGTERM', () => cleanupAndExit(143));
  process.on('SIGHUP', handleProcessSighup);
  process.on('exit', () => restoreTerminal());
  process.on('uncaughtException', (error) => failWithCleanup(error));
  process.on('unhandledRejection', (error) => failWithCleanup(error instanceof Error ? error : new Error(String(error))));
}

function clearContinueTimer() {
  if (!continueTimer) return;
  clearTimeout(continueTimer);
  continueTimer = null;
}

function clearPromptCommandTimer() {
  if (!promptCommandTimer) return;
  clearTimeout(promptCommandTimer);
  promptCommandTimer = null;
  scheduledPromptCommand = null;
}

function clearPendingPromptCommandNudgeTimer() {
  if (!pendingPromptCommandNudgeTimer) return;
  clearTimeout(pendingPromptCommandNudgeTimer);
  pendingPromptCommandNudgeTimer = null;
}

function clearPendingSubmitTimers() {
  for (const timer of pendingSubmitTimers) {
    clearTimeout(timer);
  }
  pendingSubmitTimers.clear();
  pendingSubmitSettleUntil = 0;
}

function clearInitialPromptTimer() {
  if (!initialPromptTimer) return;
  clearTimeout(initialPromptTimer);
  initialPromptTimer = null;
}

function clearInitialPromptSubmitConfirmTimer() {
  if (!initialPromptSubmitConfirmTimer) return;
  clearTimeout(initialPromptSubmitConfirmTimer);
  initialPromptSubmitConfirmTimer = null;
}

function clearRestartTimer() {
  if (!restartTimer) return;
  clearTimeout(restartTimer);
  restartTimer = null;
}

function clearForceKillTimer() {
  if (!forceKillTimer) return;
  clearTimeout(forceKillTimer);
  forceKillTimer = null;
}

function clearAutomationResumeTimer() {
  if (!automationResumeTimer) return;
  clearTimeout(automationResumeTimer);
  automationResumeTimer = null;
}

function clearStaticRecheckTimer() {
  if (!staticRecheckTimer) return;
  clearTimeout(staticRecheckTimer);
  staticRecheckTimer = null;
}

function clearAllTimers() {
  clearContinueTimer();
  clearPromptCommandTimer();
  clearPendingPromptCommandNudgeTimer();
  clearPendingSubmitTimers();
  clearInitialPromptTimer();
  clearInitialPromptSubmitConfirmTimer();
  pendingInitialPromptSubmit = null;
  clearMenuPlan();
  clearRestartTimer();
  clearForceKillTimer();
  clearAutomationResumeTimer();
  clearStaticRecheckTimer();
  clearHotkeyTimer();
  clearHeartbeatLoop();
}

function disposeActiveListeners() {
  for (const disposable of activeDisposables.splice(0)) {
    try {
      disposable?.dispose?.();
    } catch {
      // ignore
    }
  }
}

function cleanupAndExit(code) {
  if (shuttingDown) return;
  shuttingDown = true;
  clearAllTimers();
  disposeActiveListeners();

  try {
    if (activePty && typeof activePty.end === 'function') {
      activePty.end();
    }
    activePty?.kill?.();
    activeChild?.kill?.();
  } catch {
    // ignore
  }
  activePty = null;
  activeChild = null;

  restoreTerminal();
  process.exit(code);
}

function restoreTerminal() {
  unbindUserInput();
  unbindResizeHandling();
}

function failWithCleanup(error) {
  const message = error instanceof Error ? error.stack || error.message : String(error);
  console.error(`\n[fatal] ${message}\n`);
  cleanupAndExit(1);
}

function validateConfig() {
  const modes = new Set(['prompt_only', 'capacity', 'always', 'off']);
  if (!modes.has(AUTO_CONTINUE_MODE)) {
    throw new Error(`AUTO_CONTINUE_MODE=${JSON.stringify(AUTO_CONTINUE_MODE)} is invalid. Use prompt_only, capacity, always, or off.`);
  }

  const modelSwitchModes = new Set(['manage', 'set']);
  if (!modelSwitchModes.has(MODEL_SWITCH_MODE)) {
    throw new Error(`MODEL_SWITCH_MODE=${JSON.stringify(MODEL_SWITCH_MODE)} is invalid. Use manage or set.`);
  }

  const exhaustedActions = new Set(['auth', 'keep_open', 'finish']);
  if (!exhaustedActions.has(MODEL_CHAIN_EXHAUSTED_ACTION)) {
    throw new Error(`MODEL_CHAIN_EXHAUSTED_ACTION=${JSON.stringify(MODEL_CHAIN_EXHAUSTED_ACTION)} is invalid. Use auth, keep_open, or finish.`);
  }

  const numericChecks = {
    KEEP_TRY_MAX,
    TRY_AGAIN_MIN_INTERVAL_MS,
    MANUAL_OVERRIDE_MS,
    AUTOMATION_COOLDOWN_MS,
    FORCE_KILL_AFTER_MS,
    CAPACITY_RETRY_MS,
    MAX_CAPACITY_RETRY_MS,
    CAPACITY_EVENT_RESET_MS,
    CAPACITY_RECENT_MS,
    AUTO_CONTINUE_MAX_PER_EVENT,
    AUTO_RESTART_MAX_PER_WINDOW,
    AUTO_RESTART_WINDOW_MS,
    RAW_TAIL_MAX,
    NORMALIZED_TAIL_MAX,
    HOTKEY_TIMEOUT_MS,
    STATIC_RECHECK_MS,
    ACTION_RETRY_MIN_MS,
    PROMPT_SUBMIT_DELAY_MS,
    PERMISSION_RETRY_MIN_MS,
    SCREEN_MAX_BUFFER_ROWS,
    SCREEN_MAX_COLS,
    SCREEN_CAPTURE_LINES,
    MENU_SELECT_MIN_MS,
    MENU_CONFIRM_MIN_MS,
    MENU_FALLBACK_AFTER_SELECTS,
    QUICK_RECHECK_MS,
    MODEL_MANAGE_FLOW_TIMEOUT_MS,
  };

  for (const [name, value] of Object.entries(numericChecks)) {
    if (!Number.isFinite(value) || value < 0) {
      throw new Error(`${name} must be a non-negative number. Received ${JSON.stringify(value)}.`);
    }
  }
}

function currentModel() {
  return MODELS[modelIndex % MODELS.length];
}

function isModelEligibleForSession(model, options = {}) {
  const avoidPro = Boolean(options.avoidProModels);
  if (avoidPro && /pro/i.test(String(model || ''))) return false;

  if (options.avoidFullCapacityModels && isModelAtFullCapacity(model, options.capacityRows)) {
    return false;
  }

  return true;
}

function findCapacityRowForModel(model, rows = []) {
  const target = String(model || '').trim();
  if (!target || !Array.isArray(rows)) return null;
  return rows.find((row) => modelIdentifiersMatch(row?.model, target)) || null;
}

function isModelAtFullCapacity(model, rows = []) {
  const row = findCapacityRowForModel(model, rows);
  if (!row) return false;
  return Number(row.usedPercentage) >= 100;
}

function findNextEligibleModelIndexInChain(models, fromIndex, options = {}) {
  const chain = Array.isArray(models) ? models : [];
  const startIndex = Number.isInteger(fromIndex) ? fromIndex + 1 : 0;
  const fallbackFromModel = String(options.fallbackFromModel || '').trim();
  const requireFallbackDowngrade = options.requireFallbackDowngrade === true && fallbackFromModel;

  for (let index = Math.max(0, startIndex); index < chain.length; index += 1) {
    if (requireFallbackDowngrade && !isModelDowngradeFallback(fallbackFromModel, chain[index])) {
      continue;
    }
    if (isModelEligibleForSession(chain[index], options)) return index;
  }

  return -1;
}

function findNextEligibleModelIndex(fromIndex, options = {}) {
  return findNextEligibleModelIndexInChain(MODELS, fromIndex, {
    avoidProModels: avoidProModelsForSession,
    ...options,
  });
}

function isModelDowngradeFallback(fromModel, candidateModel) {
  const fromRank = modelFallbackRank(fromModel);
  const candidateRank = modelFallbackRank(candidateModel);
  if (!fromRank || !candidateRank) return true;
  if (candidateRank.generation > fromRank.generation) return false;
  if (candidateRank.generation === fromRank.generation && candidateRank.tier > fromRank.tier) {
    return false;
  }
  return true;
}

function modelFallbackRank(model) {
  const normalized = normalizeModelIdentifier(model);
  if (!normalized) return null;

  let generation = 0;
  if (/\bgemini-3\b/.test(normalized)) generation = 300;
  else if (/\bgemini-2\.5\b/.test(normalized)) generation = 250;
  else if (/\bgemini-2\b/.test(normalized)) generation = 200;
  else if (/\bgemini-1\.5\b/.test(normalized)) generation = 150;
  else if (/\bgemini-1\b/.test(normalized)) generation = 100;
  if (generation <= 0) return null;

  let tier = 0;
  if (/\bpro\b/.test(normalized)) tier = 30;
  else if (/\bflash-lite\b/.test(normalized) || /\blite\b/.test(normalized)) tier = 10;
  else if (/\bflash\b/.test(normalized)) tier = 20;

  return { generation, tier };
}

function canAutoAdvanceModelChain() {
  if (!automationEnabled || NEVER_SWITCH) return false;
  return AUTO_CONTINUE_MODE === 'capacity' || AUTO_CONTINUE_MODE === 'always';
}

function canAutoAdvanceUsageLimitModelChain() {
  if (!automationEnabled) return false;
  return AUTO_CONTINUE_MODE !== 'off';
}

function isTransitioningPlannedAction(kind) {
  switch (String(kind || '')) {
    case 'switch':
    case 'restart':
    case 'finish':
    case 'exit':
      return true;
    default:
      return false;
  }
}

function hasAnotherModelInChain() {
  return findNextEligibleModelIndex(modelIndex) >= 0;
}

function usageLimitModelFromSnapshot(snapshot) {
  if (snapshot?.kind !== 'usage_limit') return '';
  return String(snapshot?.usageLimitModel || '').trim();
}

function reconcileModelIndexFromUsageLimitModel(usageLimitModel, reason) {
  const usageIndex = findModelIndexByIdentifier(usageLimitModel, MODELS);
  if (usageIndex < 0 || usageIndex === modelIndex) return false;

  const previousModel = currentModel();
  modelIndex = usageIndex;
  console.error(`\n[${FLAVOR_LABEL}] Usage limit is for ${usageLimitModel}; correcting runner model state from ${previousModel} before ${reason}.\n`);
  return true;
}

function requestModelAdvanceOrFinish(reason, options = {}) {
  if (isTransitioningPlannedAction(plannedAction?.kind)) return 'transitioning';

  reconcileModelIndexFromVisibleTerminal('model fallback selection', {
    allowBackward: options.allowBackwardVisibleReconcile !== false,
  });
  const usageLimitModel = usageLimitModelFromSnapshot(options.snapshot);
  if (usageLimitModel) {
    reconcileModelIndexFromUsageLimitModel(usageLimitModel, 'model fallback selection');
  }
  const isUsageLimitFallback =
    options.snapshot?.kind === 'usage_limit' ||
    /^Usage limit reached\b/i.test(String(reason || '').trim());
  const fallbackFromModel = usageLimitModel || String(options.fallbackFromModel || '').trim() || currentModel();
  const nextIndex = findNextEligibleModelIndex(modelIndex, {
    avoidFullCapacityModels: options.avoidFullCapacityModels === true,
    capacityRows: options.capacityRows,
    requireFallbackDowngrade: isUsageLimitFallback || options.requireFallbackDowngrade === true,
    fallbackFromModel,
  });
  if (nextIndex >= 0) {
    const forceRelaunch = Boolean(options.forceRelaunch);
    if (activePty && !forceRelaunch && queueModelSwitchCommand(nextIndex, reason, {
      retryInitialPromptAfterSwitch: options.retryInitialPromptAfterSwitch === true,
    })) {
      scheduleStaticRecheck(QUICK_RECHECK_MS);
      return 'queued-switch';
    }

    modelIndex = nextIndex;
    const detail = String(options.forceRelaunchDetail || '').trim();
    const restartReason = detail ? `${reason} (${detail})` : reason;
    console.error(`\n[${FLAVOR_LABEL}] ${restartReason} — restarting on ${currentModel()}...\n`);
    requestLauncherAction('restart');
    return 'restart';
  }

  return handleModelChainExhausted(reason, options);
}

function handleModelChainExhausted(reason, options = {}) {
  const cleanedReason = String(reason || '').trim() || 'Model chain exhausted';

  if (MODEL_CHAIN_EXHAUSTED_ACTION === 'finish') {
    console.error(`\n[${FLAVOR_LABEL}] ${cleanedReason} — no fallback models remain. Finishing session.\n`);
    requestLauncherAction('finish', SESSION_COMPLETE_HOLD_OPEN_EXIT_CODE);
    return 'finish';
  }

  if (MODEL_CHAIN_EXHAUSTED_ACTION === 'auth') {
    if (pendingPromptCommand?.kind === 'auth') {
      scheduleStaticRecheck(QUICK_RECHECK_MS);
      return 'auth';
    }

    const authCommand = buildModelChainExhaustedAuthCommand(cleanedReason);
    if (activePty && authCommand) {
      pendingPromptCommand = authCommand;
      clearPromptCommandTimer();
      clearPendingPromptCommandNudgeTimer();
      console.error(`\n[${FLAVOR_LABEL}] ${cleanedReason} — no fallback models remain. Queueing ${authCommand.text} so you can sign in with another account.\n`);

      const snapshot = options.snapshot || currentSnapshot;
      if (!schedulePromptCommand(activeRunId, snapshot, authCommand)) {
        scheduleStaticRecheck(QUICK_RECHECK_MS);
      }
      return 'auth';
    }

    console.error(`\n[${FLAVOR_LABEL}] ${cleanedReason} — no fallback models remain. Gemini is still open; run ${AUTH_COMMAND || '/auth'} to sign in with another account.\n`);
    setAutomationEnabled(false, 'model_chain_exhausted');
    return 'keep-open';
  }

  console.error(`\n[${FLAVOR_LABEL}] ${cleanedReason} — no fallback models remain. Gemini is still open for manual recovery.\n`);
  setAutomationEnabled(false, 'model_chain_exhausted');
  return 'keep-open';
}

function finishSessionAfterModelChainExhaustion() {
  console.error(`\n[${FLAVOR_LABEL}] Model chain exhausted — all models reached capacity or usage limits. Session finished; shell will stay open.\n`);
  cleanupAndExit(SESSION_COMPLETE_HOLD_OPEN_EXIT_CODE);
}

function resolveHotkeyPrefix(name) {
  const normalized = String(name || '').trim().toLowerCase();
  const mapping = {
    'ctrl-g': { byte: 0x07, label: 'Ctrl-G' },
    '^g': { byte: 0x07, label: 'Ctrl-G' },
    'ctrl-]': { byte: 0x1d, label: 'Ctrl-]' },
    '^]': { byte: 0x1d, label: 'Ctrl-]' },
    'ctrl-t': { byte: 0x14, label: 'Ctrl-T' },
    '^t': { byte: 0x14, label: 'Ctrl-T' },
    'ctrl-\\\\': { byte: 0x1c, label: 'Ctrl-\\\\' },
    '^\\\\': { byte: 0x1c, label: 'Ctrl-\\\\' },
    'ctrl-\\': { byte: 0x1c, label: 'Ctrl-\\' },
    '^\\': { byte: 0x1c, label: 'Ctrl-\\' },
  };

  const resolved = mapping[normalized];
  if (resolved) return resolved;

  throw new Error(`Unsupported HOTKEY_PREFIX=${JSON.stringify(name)}. Use one of: ctrl-g, ctrl-], ctrl-t, ctrl-\\\\`);
}

function isEnabled(value, defaultValue) {
  if (value == null) return defaultValue;
  return String(value).toLowerCase() !== '0' && String(value).toLowerCase() !== 'false';
}

function toNumber(value, defaultValue) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : defaultValue;
}

function parseJsonArrayEnv(value) {
  if (!value) return [];
  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed) || !parsed.every((item) => typeof item === 'string')) {
      throw new Error('expected a JSON array of strings');
    }
    return parsed;
  } catch (error) {
    throw new Error(`GEMINI_WRAPPER_ARGS_JSON is invalid: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function splitListEnv(value, defaults) {
  if (!value) return defaults.map((item) => String(item));
  return String(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function normalizeModelChainExhaustedAction(value) {
  const normalized = String(value || '').trim().toLowerCase().replace(/[-\s]+/g, '_');
  switch (normalized) {
    case 'auth':
    case 'offer_auth':
    case 'reauth':
    case 'switch_account':
      return 'auth';
    case 'keep_open':
    case 'pause':
    case 'manual':
      return 'keep_open';
    case 'finish':
    case 'close':
    case 'exit':
      return 'finish';
    default:
      return normalized || 'auth';
  }
}

function shQuote(value) {
  const s = String(value);
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

function resolveFlavor(value) {
  const normalized = String(value || '').trim().toLowerCase();
  switch (normalized) {
    case 'stable':
    case 'preview':
    case 'nightly':
      return normalized;
    default:
      return 'preview';
  }
}

function defaultFlavorLabel(flavor) {
  switch (flavor) {
    case 'stable':
      return 'gemini-pty';
    case 'nightly':
      return 'gemini-nightly-pty';
    case 'preview':
    default:
      return 'gemini-preview-pty';
  }
}

function defaultWrapperForFlavor(flavor) {
  switch (flavor) {
    case 'stable':
      return 'gemini-iso';
    case 'nightly':
      return 'gemini-nightly-iso';
    case 'preview':
    default:
      return 'gemini-preview-iso';
  }
}

function defaultISOHomeForFlavor(flavor) {
  switch (flavor) {
    case 'stable':
      return path.join(os.homedir(), '.gemini-home');
    case 'nightly':
      return path.join(os.homedir(), '.gemini-nightly-home');
    case 'preview':
    default:
      return path.join(os.homedir(), '.gemini-preview-home');
  }
}

function defaultModelChainForFlavor(flavor) {
  switch (flavor) {
    case 'stable':
      return [
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
      ];
    case 'nightly':
      return [
        'gemini-3-flash-preview',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        'gemini-3-pro-preview',
        'gemini-2.5-pro',
      ];
    case 'preview':
    default:
      return [
        'gemini-3-pro-preview',
        'gemini-3-flash-preview',
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
      ];
  }
}

function defaultGeminiCliCapabilities() {
  return {
    packageName: '',
    version: '',
    packageJsonPath: '',
    startupStatsAutomationSupported: true,
    startupStatsAutomationDisabledReason: '',
    statsSessionAutomationSupported: true,
    statsSessionAutomationDisabledReason: '',
    systemSettingsOverride: null,
    systemSettingsOverrideReason: '',
  };
}

function resolveGeminiCliCapabilities(wrapperInfo) {
  const packageInfo = inspectGeminiCliPackage(wrapperInfo);
  const startupStatsDisabledReason = resolveStartupStatsAutomationDisabledReason(packageInfo);
  const disabledReason = resolveStatsSessionAutomationDisabledReason(packageInfo);
  const systemSettingsOverride = resolveGeminiCliSystemSettingsOverride(packageInfo);
  const systemSettingsOverrideReason = resolveGeminiCliSystemSettingsOverrideReason(packageInfo);

  return {
    ...packageInfo,
    startupStatsAutomationSupported: !startupStatsDisabledReason,
    startupStatsAutomationDisabledReason: startupStatsDisabledReason,
    statsSessionAutomationSupported: !disabledReason,
    statsSessionAutomationDisabledReason: disabledReason,
    systemSettingsOverride,
    systemSettingsOverrideReason,
  };
}

function inspectGeminiCliPackage(wrapperInfo) {
  const fallback = defaultGeminiCliCapabilities();
  const candidates = [];

  for (const candidate of [wrapperInfo?.realPath, wrapperInfo?.resolvedPath, wrapperInfo?.execPath]) {
    const value = String(candidate || '').trim();
    if (!value || candidates.includes(value)) continue;
    candidates.push(value);
  }

  for (const candidate of candidates) {
    const packageJsonPath = findNearestPackageJson(candidate);
    if (!packageJsonPath) continue;

    try {
      const parsed = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
      if (parsed?.name !== '@google/gemini-cli') continue;

      return {
        packageName: parsed.name,
        version: normalizeVersionString(parsed.version),
        packageJsonPath,
      };
    } catch {
      // ignore invalid package.json files while walking up from wrapper targets
    }
  }

  return fallback;
}

function findNearestPackageJson(candidatePath) {
  let current = String(candidatePath || '').trim();
  if (!current) return '';

  try {
    const stat = fs.statSync(current);
    if (!stat.isDirectory()) {
      current = path.dirname(current);
    }
  } catch {
    current = path.dirname(current);
  }

  while (current && current !== path.dirname(current)) {
    const packageJsonPath = path.join(current, 'package.json');
    if (fs.existsSync(packageJsonPath)) {
      return packageJsonPath;
    }
    current = path.dirname(current);
  }

  const rootPackageJsonPath = path.join(current || path.sep, 'package.json');
  return fs.existsSync(rootPackageJsonPath) ? rootPackageJsonPath : '';
}

function normalizeVersionString(version) {
  return String(version || '').trim().replace(/^v/i, '');
}

function resolveStartupStatsAutomationDisabledReason(_packageInfo) {
  return '';
}

function resolveStatsSessionAutomationDisabledReason(packageInfo) {
  if (packageInfo?.packageName !== '@google/gemini-cli') return '';
  if (normalizeVersionString(packageInfo?.version) === '0.32.1') {
    return 'Gemini CLI 0.32.1 crashes on /stats session ("data.slice is not a function"), so /stats session automation is disabled for session-scoped model management.';
  }
  return '';
}

function resolveGeminiCliSystemSettingsOverride(packageInfo) {
  if (packageInfo?.packageName !== '@google/gemini-cli') return null;
  return {
    general: {
      enableAutoUpdate: false,
      enableAutoUpdateNotification: false,
    },
  };
}

function resolveGeminiCliSystemSettingsOverrideReason(packageInfo) {
  if (packageInfo?.packageName !== '@google/gemini-cli') return '';
  if (normalizeVersionString(packageInfo?.version) === '0.32.1') {
    return 'Gemini CLI 0.32.1 self-update checks are disabled for this launch';
  }
  const version = normalizeVersionString(packageInfo?.version);
  return version
    ? `Gemini CLI ${version} self-update checks are disabled for this launch`
    : 'Gemini CLI self-update checks are disabled for this launch';
}

export const _test = {
  RUNNER_BUILD_ID,
  normalizeTerminalText,
  detectSnapshotFromText,
  detectContinuePrompt,
  buildPromptContext,
  extractPromptInputText,
  automationPromptInputCommandLines,
  hasLiveAuthWait,
  hasAuthRestartRequiredPrompt,
  buildChildEnv,
  buildGeminiArgs,
  shouldAutoContinuePrompt,
  selectedAutoContinueCommand,
  shouldUseContinueFallbackPrompt,
  hasRepeatedConcludedSessionText,
  concludedSessionKeywordBlockCount,
  concludedSessionKeywordFamilies,
  hasConcludedSessionText,
  effectiveAutoContinueMode,
  manualInputSubmitsPrompt,
  shouldForceAlwaysAutoContinueOnAutomationEnable,
  shouldLaunchInitialPromptWithLaunchArgs,
  shouldRequireStartupStatsBeforeInitialPrompt,
  shouldDelayInitialPromptForStartupStats,
  isStartupPromptCommandKind,
  resolveStartupStatsBlockReason,
  startupPipelineLabel,
  startupPromptGateLabel,
  startupPromptDeliveryQueueLabel,
  startupSequenceQueuedLabel,
  buildStartupCommandPipeline,
  buildPostAuthTelemetryCommand,
  buildNextStartupCommand,
  isStartupModelUnavailableReason,
  shouldRequeueStartupCommand,
  isLikelyAutomationPromptInput,
  buildStartupClearCommand,
  buildStartupStatsCommand,
  buildStartupModelCommand,
  buildModelChainExhaustedAuthCommand,
  buildStartupStatsFallbackCommand,
  buildModelManageStarterCommand,
  buildModelSwitchCommand,
  buildDirectModelSwitchCommand,
  shouldSubmitWithDelayedEnter,
  shouldUseAutocompleteSafeSlashSubmit,
  promptCommandScheduleDelay,
  promptInputMatchesSubmittedPrompt,
  isInitialPromptSubmissionConfirmed,
  describePromptCommandSendDetail,
  isPromptCommandStillCurrent,
  promptCommandPriority,
  extractStartupStatsSnapshot,
  canSendPromptCommandWithoutVisiblePrompt,
  hasStartupClearSettled,
  hasStartupStatsCaptureSettled,
  hasStartupModelCapacityClosed,
  describeStartupStatsCapture,
  describeStartupModelCapacityCapture,
  extractStartupModelCapacitySnapshot,
  extractVisibleCurrentModel,
  isDirectModelSwitchConfirmed,
  resolveDirectModelSwitchConfirmation,
  findModelIndexByIdentifier,
  resolveModelIndexFromVisibleCurrentModel,
  resolveModelIndexFromVisibleTerminalTexts,
  shouldRelaunchForBlockedUsageLimit,
  shouldSwitchImmediatelyForPromptUsageLimit,
  resolvePendingModelSwitchTargetForUsageLimit,
  resolveStartupAutoModelOption,
  normalizeModelChainExhaustedAction,
  resolveStartupStatsAutomationDisabledReason,
  resolveStatsSessionFallbackCommand,
  ensureGeminiCliCompatibilitySystemSettings,
  resolveGeminiCliCapabilities,
  inspectGeminiCliPackage,
  resolveGeminiCliSystemSettingsOverride,
  resolveGeminiCliSystemSettingsOverrideReason,
  resolveStatsSessionAutomationDisabledReason,
  findNextEligibleModelIndexInChain,
  isTransitioningPlannedAction,
  resolvePendingModelManageRecoveryAction,
  shouldFallbackToDirectSpawnForPtyError,
  isBenignStdoutWriteError,
  findModelManageRoutingMenuBlock,
  findModelManageModelListBlock,
  extractMenuBlocks,
  parseOptionLine,
  normalizeLabel,
  findFallbackCapacityMenuBlock,
  resolveCapacityKeepOption,
  resolveCapacitySwitchOption,
  shouldIgnoreProcessSighupForState,
  resolvePythonPtyExecutable,
  createPythonPtyBackend,
  prepareFreshWorkspaceSessionForPromptLaunch,
  alternateWorkspacePathAlias,
  VirtualScreen,
};

const isModuleEntry = Boolean(
  process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))
);

if (isModuleEntry) {
  main().catch((error) => {
    failWithCleanup(error instanceof Error ? error : new Error(String(error)));
  });
}
