#!/usr/bin/env bash
set -euo pipefail

DB_NAME="online_store_lab4"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_TMP="/tmp/lab4_permissions_test.sql"

echo "=== Lab 4: проверка ролей PostgreSQL ==="

cp "$PROJECT_DIR/sql/permissions_test.sql" "$SQL_TMP"


cd /tmp
sudo -u postgres psql -d "$DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -f "$SQL_TMP"

