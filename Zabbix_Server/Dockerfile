# =============================================================================
# zabbix-init/Dockerfile
#
# zabbix-server-mysql 公式イメージをベースに、
# DB 自動初期化エントリーポイントを追加する薄いラッパー。
#
# イメージ本体は変更せず entrypoint だけ差し替えるため、
# Zabbix バージョンアップ時は .env の ZABBIX_VERSION を変えるだけでよい。
# =============================================================================

ARG ZABBIX_VERSION
FROM zabbix/zabbix-server-mysql:${ZABBIX_VERSION}

USER root

ARG ENTRY_POINT

COPY ${ENTRY_POINT} /usr/local/bin/${ENTRY_POINT}
RUN chmod +x /usr/local/bin/${ENTRY_POINT}

# 公式イメージのデフォルトユーザに戻す
USER 1997

