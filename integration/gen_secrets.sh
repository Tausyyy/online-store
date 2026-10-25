#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ -f "$ENV_FILE" && $FORCE -eq 0 ]]; then
    echo "Файл .env уже существует, пароли не изменены (для замены: --force)"
    exit 0
fi

rand() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 24
    else
        head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

umask 077
cat > "$ENV_FILE" <<ENV
POSTGRES_PASSWORD=$(rand)
LAB4_ADMIN_PASSWORD=$(rand)
LAB4_APP_PASSWORD=$(rand)
LAB4_ANALYST_PASSWORD=$(rand)
REPL_POSTGRES_PASSWORD=$(rand)
REPLICATOR_PASSWORD=$(rand)
ENV
chmod 600 "$ENV_FILE" 2>/dev/null || true

echo "Создан .env со случайными паролями (в Git не попадает, см. .gitignore)"
