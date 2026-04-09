#!/bin/bash
# =============================================================================
# start.sh  -  Zabbix Docker 環境 エントリーポイント
#
# 動作概要:
#   1. .env から設定値を読み込む
#   2. docker compose で全コンテナを起動
#   3. DB(MySQL) の起動完了をポーリングして待機
#   4. Zabbix テーブルが存在しない(初回)場合のみ
#      zabbix-server コンテナ内の schema.sql.gz / data.sql.gz を DB に投入
#   5. 以降は何もせずそのまま稼働を継続
#
# 使い方:
#   chmod +x start.sh
#   ./start.sh
# =============================================================================

set -euo pipefail

# ---------- .env 読み込み ----------
ENV_FILE="$(dirname "$0")/.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "ERROR: .env が見つかりません: ${ENV_FILE}"
    exit 1
fi
# コメント行・空行を除いて export
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# ---------- コンテナ名 (docker-compose.yml の container_name と合わせる) ----------
DB_CONTAINER="${DB_CONTAINER_NAME}"
ZBX_CONTAINER="${ZABBIX_CONTAINER_NAME}"

# schema / data SQL のパス (zabbix-server-mysql イメージ内の固定パス)
SCHEMA_SQL="/usr/share/doc/zabbix-server-mysql/schema.sql.gz"
DATA_SQL="/usr/share/doc/zabbix-server-mysql/data.sql.gz"

# DB 起動待ち最大試行回数 (×2秒)
MAX_WAIT=60

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ------- 1. コンテナ群を起動 -------
log "docker compose を起動します..."
docker compose up -d
log "コンテナ起動コマンド完了。DB の準備を待ちます..."

# ------- 2. MySQL が応答するまで待機 -------
count=0
until docker exec "${DB_CONTAINER}" \
        mysqladmin ping -h localhost \
        -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
        --silent 2>/dev/null; do
    count=$((count + 1))
    if [ "${count}" -ge "${MAX_WAIT}" ]; then
        log "ERROR: MySQL が ${MAX_WAIT} 回待っても応答しません。終了します。"
        exit 1
    fi
    log "MySQL 起動待ち... (${count}/${MAX_WAIT})"
    sleep 2
done
log "MySQL 起動確認OK。"

# ------- 3. 初回かどうか確認 (users テーブルの存在で判定) -------
TABLE_EXISTS=$(docker exec "${DB_CONTAINER}" \
    mysql -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" \
    --skip-column-names -e \
    "SELECT COUNT(*) FROM information_schema.tables
     WHERE table_schema='${MYSQL_DATABASE}' AND table_name='users';" \
    2>/dev/null || echo "0")

if [ "${TABLE_EXISTS}" = "0" ] || [ "${TABLE_EXISTS}" = "" ]; then
    log "初回起動を検出。Zabbix DB を初期化します..."

    log "schema.sql を適用中..."
    docker exec "${ZBX_CONTAINER}" sh -c "zcat ${SCHEMA_SQL}" \
        | docker exec -i "${DB_CONTAINER}" \
            mysql -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}"

    log "data.sql を適用中..."
    docker exec "${ZBX_CONTAINER}" sh -c "zcat ${DATA_SQL}" \
        | docker exec -i "${DB_CONTAINER}" \
            mysql -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}"

    log "DB 初期化が完了しました。"
    log "Zabbix サーバを再起動して初期化済み DB に接続させます..."
    docker compose restart zabbix-server
    log "再起動完了。"
else
    log "既存の Zabbix DB を検出。初期化をスキップします。"
fi

log "=========================================="
log "Zabbix 起動完了"
log "  Web UI : http://localhost:${WEB_PORT}"
log "  User   : Admin"
log "  Pass   : zabbix"
log "=========================================="
