#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAIL=0
ok()   { echo "OK:   $*"; }
bad()  { echo "FAIL: $*"; FAIL=1; }

[[ -f .env ]] && ok ".env существует" || bad ".env не найден"

if [[ -f .env ]]; then
    perms="$(stat -c '%a' .env 2>/dev/null || stat -f '%Lp' .env 2>/dev/null || echo '?')"
    if [[ "$perms" == "600" || "$perms" == "?" ]]; then ok "права на .env: $perms"; else bad "права на .env: $perms (ожидается 600)"; fi
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git check-ignore -q .env; then ok ".env игнорируется Git"; else bad ".env не в .gitignore"; fi

    if git ls-files --error-unmatch .env >/dev/null 2>&1; then bad ".env отслеживается Git"; else ok ".env не отслеживается Git"; fi

    leaked=0
    while IFS='=' read -r key value; do
        [[ -z "$key" || -z "$value" ]] && continue
        if git grep -qF -e "$value" -- . ':!.env' 2>/dev/null; then
            bad "значение $key найдено в файлах под контролем Git"
            leaked=1
        fi
    done < .env
    [[ $leaked -eq 0 ]] && ok "значения паролей из .env не встречаются в отслеживаемых файлах"
else
    echo "SKIP: каталог не является Git-репозиторием, проверка Git пропущена"
fi

[[ -f .env.example ]] && ok ".env.example присутствует" || bad ".env.example отсутствует"
if [[ -f .env.example ]] && ! grep -q 'change_me' .env.example; then bad ".env.example содержит не шаблонные значения"; fi

[[ $FAIL -eq 0 ]] && echo "ИТОГ: секреты хранятся вне Git" || echo "ИТОГ: есть замечания"
exit $FAIL
