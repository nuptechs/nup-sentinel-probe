#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# validate-changed.sh (genérico) — valida SÓ o que mudou vs a branch default.
#
# Auto-detecta o ferramental do repo (biome | eslint; vitest) e roda apenas nos
# arquivos alterados, pra NÃO travar push por dívida legada do resto do repo.
# Fail-soft: sem node_modules / sem linter → avisa e libera.
#
# Pensado pra ser chamado pelo pre-push E, no futuro, pelo LocalTestRunner do
# loop self-healing (ADR-044): contrato simples — exit 0 = ok, exit 1 = achou
# problema, saída legível pra um agente ler e corrigir.
#
# Config opcional por repo em .githooks/validate.config (ex.: RUN_TESTS=1).
# Flags por env: RUN_TESTS=1 (vitest --changed) · RUN_TYPECHECK=1 (script do repo)
#                BASE_REF=origin/x · SKIP via 'git push --no-verify'.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT" || exit 2

# Config por repo (não falha se ausente).
# shellcheck disable=SC1091
[ -f .githooks/validate.config ] && . .githooks/validate.config

detect_base_ref() {
  local h
  h="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$h" ] && { echo "$h"; return; }
  for b in origin/main origin/master; do
    git rev-parse --verify --quiet "$b" >/dev/null 2>&1 && { echo "$b"; return; }
  done
}
BASE_REF="${BASE_REF:-$(detect_base_ref)}"
BASE=""
[ -n "$BASE_REF" ] && BASE="$(git merge-base HEAD "$BASE_REF" 2>/dev/null || true)"
[ -z "$BASE" ] && BASE="$(git rev-parse HEAD~1 2>/dev/null || echo HEAD)"

CHANGED="$(git diff --name-only --diff-filter=ACMR "$BASE"...HEAD -- \
  '*.js' '*.mjs' '*.cjs' '*.jsx' '*.ts' '*.mts' '*.cts' '*.tsx' '*.vue' 2>/dev/null)"

if [ -z "$CHANGED" ]; then
  echo "✓ Nada de código mudou vs ${BASE_REF:-HEAD~1} — pulando validação."
  exit 0
fi

N="$(printf '%s\n' "$CHANGED" | sed '/^$/d' | wc -l | tr -d ' ')"
echo "▶ Validando $N arquivo(s) mudado(s) vs ${BASE:0:9}..."

if [ ! -d node_modules ]; then
  echo "  ⚠ node_modules ausente (rode npm install) — validação pulada."
  exit 0
fi

FAIL=0

# ── Detecta o linter pelo script 'lint' do repo (sinal mais confiável) ──────
file_exists_glob() { for f in $1; do [ -e "$f" ] && return 0; done; return 1; }
lint_script="$(node -e "process.stdout.write((require('./package.json').scripts||{}).lint||'')" 2>/dev/null || true)"

LINTER=none
if [ -f biome.json ] || [ -f biome.jsonc ] || printf '%s' "$lint_script" | grep -qi biome; then
  LINTER=biome
elif printf '%s' "$lint_script" | grep -qi eslint || file_exists_glob 'eslint.config.*' || file_exists_glob '.eslintrc*'; then
  LINTER=eslint
elif printf '%s' "$lint_script" | grep -qi turbo; then
  LINTER=turbo
fi

# ── Lint (só changed) ───────────────────────────────────────────────────────
case "$LINTER" in
  biome)
    if [ -x node_modules/.bin/biome ]; then
      echo "  → biome lint (changed)..."
      # 'lint' e não 'check': não bloqueia por formatação/ordem-de-import.
      # shellcheck disable=SC2086
      npx --no-install biome lint $CHANGED || FAIL=1
    else echo "  ⓘ biome detectado mas binário ausente — pulando lint."; fi
    ;;
  eslint)
    if [ -x node_modules/.bin/eslint ]; then
      echo "  → eslint (changed)..."
      # shellcheck disable=SC2086
      npx --no-install eslint --no-warn-ignored $CHANGED || FAIL=1
    else echo "  ⓘ eslint detectado mas binário ausente — pulando lint."; fi
    ;;
  turbo)
    # Monorepo turbo: lint só dos pacotes afetados desde a base.
    echo "  → turbo run lint (pacotes afetados)..."
    npx --no-install turbo run lint --filter="...[$BASE]" || FAIL=1
    ;;
  *)
    echo "  ⓘ sem linter detectado — pulando lint."
    ;;
esac

# ── (precisão) Testes do que mudou via vitest --changed ─────────────────────
if [ "${RUN_TESTS:-0}" = "1" ]; then
  if [ -x node_modules/.bin/vitest ]; then
    echo "  → vitest run --changed..."
    npx --no-install vitest run --changed "$BASE" --passWithNoTests || FAIL=1
  else
    echo "  ⓘ RUN_TESTS=1 mas sem vitest — pulando testes."
  fi
fi

# ── (precisão) Typecheck via script do repo (projeto inteiro) ───────────────
if [ "${RUN_TYPECHECK:-0}" = "1" ]; then
  TC="$(node -e "const s=require('./package.json').scripts||{};for(const k of ['typecheck','type-check','check']){if(s[k]){console.log(k);break}}" 2>/dev/null || true)"
  if [ -n "$TC" ]; then
    echo "  → npm run $TC..."
    npm run -s "$TC" || FAIL=1
  else
    echo "  ⓘ RUN_TYPECHECK=1 mas sem script de typecheck — pulando."
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "✗ Validação falhou — conserte os problemas acima e tente de novo."
  echo "  Emergência: 'git push --no-verify' pula o hook por completo."
  exit 1
fi

echo "✓ Validação passou."
exit 0
