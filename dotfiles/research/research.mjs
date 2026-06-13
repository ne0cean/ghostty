#!/usr/bin/env node
// research.mjs — Ghostty 파워유저 툴킷 전용 리서치 러너
// a-team scripts/research-daemon.mjs 패턴을 참고한 경량 self-contained 버전.
// 카테고리별로 claude --print 를 spawn → 에이전트가 웹 리서치 후 노트 파일 작성.
//
// 사용법:
//   node research.mjs --list                 카테고리 목록
//   node research.mjs --once ghostty-features 단일 카테고리 1회
//   node research.mjs --once all             전체 순환 (사이클 간 2분 대기)
//   node research.mjs --daemon               10분 유휴 감지 후 자율 순환
//
// ⚠️ 리서치 전용: 에이전트는 코드 변경 금지, 노트 파일에만 기록.

import { existsSync, mkdirSync, appendFileSync, statSync } from 'node:fs';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RESEARCH_DIR = __dirname;                 // dotfiles/research
const REPO_ROOT = dirname(__dirname);           // dotfiles
const NOTES_DIR = join(RESEARCH_DIR, 'notes');

const CONFIG = {
  maxBudgetUsd: '0.50',     // 사이클당 예산
  cycleGapMs: 2 * 60 * 1000,
  idleThresholdMs: 10 * 60 * 1000,
  idlePollMs: 60 * 1000,
};

// ─── 카테고리: Ghostty 파워유저 툴킷에 맞춤 ──────────────────────────────────
const CATEGORIES = ['ghostty-features', 'terminal-power', 'shell-ux', 'workflow-automation'];

const PROJECT_CONTEXT = `
이 프로젝트는 "Ghostty 파워유저 툴킷" (ne0cean/ghostty dotfiles)입니다.
- 위치: ${REPO_ROOT}
- 현재 기능: 이미지 paste(Cmd+Shift+V 백업, Claude Code는 Ctrl+V), broadcast input,
  ssht(SSH 새 창), 라인 타임스탬프, triggers(커맨드 후크), quick terminal,
  notify-on-command-finish, profile auto-switch(SSH 배경색), 기능 발견 시스템
  (ghostty-help / ghostty-tip / 상황 힌트), write_screen_file.
- 핵심 파일: ${REPO_ROOT}/features-registry.conf, ${REPO_ROOT}/scripts/*,
  ${REPO_ROOT}/zsh-integration.zsh, ${REPO_ROOT}/config/ghostty
- 목표: iTerm2/kitty/WezTerm/Warp 대비 "차별화된" 터미널 경험을 1인이 유지.
`;

const BASE_RULES = (category, ts) => `
## 역할 & 규칙
당신은 순수 리서치 에이전트입니다. **코드를 변경하지 않습니다.**

절대 금지: 코드 파일 편집(스크립트/config), git commit/push, 의존성 설치.
허용: WebSearch / WebFetch 로 외부 조사, 프로젝트 파일 읽기(Read/Grep), 그리고
**노트 파일 1개만 Write/Edit** (아래 경로).

반드시:
1. 각 섹션을 완료할 때마다 즉시 노트 파일에 추가 저장 (몰아쓰기 금지).
2. 예산 경고가 보이면 진행분을 저장하고 "## 다음 사이클 제안" 작성 후 종료.

## 노트 파일 (이 파일만 쓰기 허용)
${join(NOTES_DIR, category, ts + '.md')}

형식:
\`\`\`markdown
# [${category}] 리서치 — ${ts}

## 분석 범위
- (읽은 프로젝트 파일 / 조사한 외부 소스)

## 핵심 발견
- (경쟁 터미널의 기능, Ghostty 신규 capability, 베스트 프랙티스 — 출처 URL 포함)

## 이 툴킷에 추가할 제안 (우선순위순)
1. **[높음]** 제목 — 무엇을/왜, 구현 파일, 예상 난이도, Ghostty 네이티브로 가능한지 여부
2. **[중간]** ...
3. **[낮음]** ...

## 다음 사이클 제안
- (이어서 조사할 것)
\`\`\`
`;

const TASKS = {
  'ghostty-features': `
## 리서치 태스크: Ghostty 네이티브 미사용 기능 발굴
1. 먼저 ${REPO_ROOT}/config/ghostty 와 features-registry.conf 를 읽어 현재 쓰는 기능 파악.
2. 웹에서 Ghostty 최신 릴리스/문서(ghostty.org/docs, 최근 GitHub 릴리스 노트)를 조사해,
   **아직 이 툴킷이 안 쓰는 유용한 config 옵션·keybind 액션·기능**을 찾는다.
3. 각 발견에 대해: 어떤 워크플로를 개선하는지, config 한 줄 예시, 난이도.`,
  'terminal-power': `
## 리서치 태스크: 경쟁 터미널 차별화 기능 이식
1. kitty / WezTerm / iTerm2 / Warp 의 파워유저 기능 중 이 툴킷에 없는 것을 웹에서 조사.
   (예: kitty graphics/hints/remote-control, WezTerm 멀티플렉싱, Warp blocks 등)
2. 현재 scripts/ 와 features-registry.conf 와 비교해 **빈 칸(gap)** 식별.
3. 각 후보: Ghostty에서 재현 가능 여부(네이티브 vs 스크립트), 구현 스케치, 난이도.`,
  'shell-ux': `
## 리서치 태스크: zsh/셸 통합 UX 개선
1. ${REPO_ROOT}/zsh-integration.zsh 를 읽어 현재 ZLE 위젯/훅/프롬프트 통합 파악.
2. 웹에서 셸 통합 베스트 프랙티스(OSC 7/133 시맨틱 프롬프트, 셸 통합 마커,
   completion UX, fzf 연동 등)를 조사.
3. 각 제안: 어떤 마찰을 줄이는지, 통합 지점, 난이도.`,
  'workflow-automation': `
## 리서치 태스크: 터미널 자동화/멀티터미널 확장
1. scripts/ghostty-broadcast, scripts/ssht, triggers 파일을 읽어 현재 자동화 파악.
2. 웹에서 터미널 자동화 패턴(세션 복원, 브로드캐스트, 트리거/훅, 알림 라우팅)을 조사.
3. 각 제안: 기존 스크립트 확장 vs 신규, 구현 스케치, 난이도.`,
};

// ─── 유틸 ────────────────────────────────────────────────────────────────────
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  appendFileSync(join(RESEARCH_DIR, 'research.log'), line);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function ensureDirs() {
  for (const c of CATEGORIES) mkdirSync(join(NOTES_DIR, c), { recursive: true });
}

function findClaude() {
  const home = process.env.HOME || '';
  const candidates = [
    `${home}/claude-remote/bin/claude`,   // 이 머신의 실경로 (claude alias 대상)
    '/opt/homebrew/bin/claude',
    '/usr/local/bin/claude',
  ];
  for (const p of candidates) if (existsSync(p)) return p;
  const r = spawnSync('which', ['claude'], { encoding: 'utf8' });
  return r.stdout?.trim() || 'claude';
}

function buildPrompt(category, ts) {
  return `${PROJECT_CONTEXT}\n${BASE_RULES(category, ts)}\n${TASKS[category]}\n\n먼저 노트 파일의 "분석 범위" 섹션부터 생성한 뒤 단계별로 진행하세요.`;
}

function tsNow() {
  // 파일명 안전 ISO (콜론 제거)
  return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
}

async function runCycle(category) {
  if (!CATEGORIES.includes(category)) {
    log(`[ERR] 알 수 없는 카테고리: ${category} (사용 가능: ${CATEGORIES.join(', ')})`);
    return 1;
  }
  ensureDirs();
  const ts = tsNow();
  const noteFile = join(NOTES_DIR, category, ts + '.md');
  const claudePath = findClaude();
  log(`[CYCLE] 시작: ${category} → ${noteFile}`);

  const args = [
    '--print',
    '--permission-mode', 'acceptEdits',
    '--max-budget-usd', CONFIG.maxBudgetUsd,
    buildPrompt(category, ts),
  ];

  return await new Promise((resolve) => {
    const child = spawn(claudePath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.on('data', (d) => process.stdout.write(d));
    child.stderr.on('data', (d) => appendFileSync(join(RESEARCH_DIR, 'research.log'), d));
    child.on('close', (code) => {
      const ok = existsSync(noteFile);
      log(`[CYCLE] 종료: ${category} (exit ${code}, 노트 ${ok ? '작성됨' : '없음'})`);
      resolve(code ?? 0);
    });
    child.on('error', (e) => { log(`[ERR] spawn 실패: ${e.message}`); resolve(1); });
  });
}

async function runAll() {
  for (let i = 0; i < CATEGORIES.length; i++) {
    await runCycle(CATEGORIES[i]);
    if (i < CATEGORIES.length - 1) {
      log(`[GAP] ${CONFIG.cycleGapMs / 1000}s 대기...`);
      await sleep(CONFIG.cycleGapMs);
    }
  }
  log('[DONE] 전체 순환 완료');
}

function idleSeconds() {
  // ioreg HIDIdleTime (ns) → 초. macOS 전용. 실패 시 0.
  const r = spawnSync('sh', ['-c',
    `ioreg -c IOHIDSystem | awk '/HIDIdleTime/{print int($NF/1000000000); exit}'`],
    { encoding: 'utf8' });
  return parseInt(r.stdout?.trim() || '0', 10) || 0;
}

async function daemon() {
  log('[DAEMON] 시작 — 10분 유휴 감지 후 카테고리 순환');
  let idx = 0;
  for (;;) {
    if (idleSeconds() * 1000 >= CONFIG.idleThresholdMs) {
      const cat = CATEGORIES[idx % CATEGORIES.length];
      log(`[DAEMON] 유휴 감지 → ${cat}`);
      await runCycle(cat);
      idx++;
      await sleep(CONFIG.cycleGapMs);
    } else {
      await sleep(CONFIG.idlePollMs);
    }
  }
}

// ─── CLI ──────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
if (argv[0] === '--list' || argv.length === 0) {
  console.log('Ghostty 리서치 카테고리:');
  for (const c of CATEGORIES) console.log(`  - ${c}`);
  console.log('\n사용: node research.mjs --once <카테고리|all> | --daemon | --list');
} else if (argv[0] === '--once') {
  const target = argv[1];
  if (target === 'all') await runAll();
  else await runCycle(target || CATEGORIES[0]);
} else if (argv[0] === '--daemon') {
  await daemon();
} else {
  console.error(`알 수 없는 인수: ${argv.join(' ')}`);
  process.exit(1);
}
