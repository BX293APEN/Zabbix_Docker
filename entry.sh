#!/bin/bash
# =============================================================================
# entrypoint.sh  -  Zabbix Server カスタムエントリーポイント
#
# 役割:
#   1. MySQL が応答するまで待機
#   2. Zabbix テーブルが存在しない(初回)場合のみ schema / data を投入
#   3. 本来の zabbix_server エントリーポイントへ exec で引き渡す
#
# ※ このスクリプトは zabbix-server コンテナ内で動作する
#    DB 接続情報は docker-compose.yml の environment / .env から渡される
# =============================================================================

set -euo pipefail

log() { echo "[entrypoint $(date '+%H:%M:%S')] $*"; }

# ---------- 環境変数 (docker-compose.yml の environment で注入される) ----------
: "${DB_SERVER_HOST:?DB_SERVER_HOST が未設定です}"
: "${DB_SERVER_PORT:=3306}"
: "${MYSQL_DATABASE:?MYSQL_DATABASE が未設定です}"
: "${MYSQL_USER:?MYSQL_USER が未設定です}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD が未設定です}"

# SQLファイルは .env の ZBX_CREATE_SQL で変更可能
: "${ZBX_CREATE_SQL:=/usr/share/doc/zabbix-server-mysql/create.sql.gz}"
MYSQL_OPTS="--ssl=false"
MAX_WAIT=3

# ---------- MySQL 起動待ち ----------
log "MySQL (${DB_SERVER_HOST}:${DB_SERVER_PORT}) の起動を待ちます..."
count=0
until mysqladmin ping ${MYSQL_OPTS} \
        -h "${DB_SERVER_HOST}" \
        -P "${DB_SERVER_PORT}" \
        -u "${MYSQL_USER}" \
        -p"${MYSQL_PASSWORD}" \
        --silent 2>/dev/null; do
    count=$((count + 1))
    if [ "${count}" -ge "${MAX_WAIT}" ]; then
        log "ERROR: MySQL が応答しません (${MAX_WAIT}回試行)。終了します。"
        exit 1
    fi
    log "待機中... (${count}/${MAX_WAIT})"
    sleep 2
done
log "MySQL 接続OK。"

# ---------- 初回判定 ----------
TABLE_EXISTS=$(mysql ${MYSQL_OPTS} \
    -h "${DB_SERVER_HOST}" \
    -P "${DB_SERVER_PORT}" \
    -u "${MYSQL_USER}" \
    -p"${MYSQL_PASSWORD}" \
    "${MYSQL_DATABASE}" \
    --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema='${MYSQL_DATABASE}' AND table_name='users';" \
    2>/dev/null || echo "0")

if [ "${TABLE_EXISTS}" = "0" ] || [ -z "${TABLE_EXISTS}" ]; then
    log "初回起動 — DB を初期化します..."

    log "SQL を適用中... (${ZBX_CREATE_SQL})"
    zcat "${ZBX_CREATE_SQL}" | mysql ${MYSQL_OPTS} \
        -h "${DB_SERVER_HOST}" \
        -P "${DB_SERVER_PORT}" \
        -u "${MYSQL_USER}" \
        -p"${MYSQL_PASSWORD}" \
        "${MYSQL_DATABASE}"

    log "DB 初期化完了。"
else
    log "既存 DB を検出 — 初期化をスキップします。"
fi

# ---------- 本来の Zabbix Server エントリーポイントへ ----------
log "Zabbix Server を起動します..."
exec /usr/sbin/zabbix_server --foreground "$@"
