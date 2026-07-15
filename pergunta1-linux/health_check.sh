#!/usr/bin/env bash
#
# health_check.sh - Monitor de saude da stack Nginx + PHP-FPM
# -----------------------------------------------------------------------------
# Verifica se Nginx e PHP-FPM estao (1) ativos no gerenciador de servicos
# e (2) respondendo de fato. Registra em log e alerta quando algo cai.
# Seguro para rodar via cron (sem sobreposicao, sem spam de alerta).
#
# Uso:   ./health_check.sh
# Cron:  */2 * * * * /caminho/health_check.sh
# Saida: 0 = tudo ok | 1 = falha detectada
# -----------------------------------------------------------------------------

set -uo pipefail

# --- Configuracao (troque via variavel de ambiente; padroes seguros) ---------
readonly NGINX_SERVICE="${NGINX_SERVICE:-nginx}"
readonly PHP_SERVICE="${PHP_SERVICE:-php8.1-fpm}"
readonly PHP_FPM_SOCKET="${PHP_FPM_SOCKET:-/run/php/php8.1-fpm.sock}"
readonly HEALTH_URL="${HEALTH_URL:-http://localhost:8090/index.php}"
readonly HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"

readonly LOG_FILE="${LOG_FILE:-/var/log/health_check.log}"
readonly STATE_DIR="${STATE_DIR:-/var/tmp/health_check}"
readonly LOCK_FILE="${LOCK_FILE:-/var/tmp/health_check.lock}"

# --- Funcoes utilitarias -----------------------------------------------------

# timestamp: retorna data e hora no formato padrao
ts() { date '+%F %T'; }

# log: grava a mensagem no arquivo de log e tambem na saida de erro
# uso: log "NIVEL" "mensagem"
log() {
    echo "$(ts) [$1] $2" | tee -a "$LOG_FILE" >&2
}

# --- Alerta -----------------------------------------------------------------

# alert: dispara alerta apenas quando o estado MUDA (ok->down ou down->ok).
# Guarda o ultimo estado em arquivo para nao repetir alerta a cada execucao.
# uso: alert "componente" "status"   (status: "up" ou "down")
alert() {
    local component="$1"
    local status="$2"
    local state_file="${STATE_DIR}/${component}.state"

    # le o estado anterior (assume "up" na primeira vez)
    local previous="up"
    [ -f "$state_file" ] && previous="$(cat "$state_file")"

    # so age se o estado mudou
    if [ "$status" != "$previous" ]; then
        echo "$status" > "$state_file"
        if [ "$status" = "down" ]; then
            log "ALERT" "$component caiu"
        else
            log "RECOVER" "$component voltou ao normal"
        fi
    fi
}

# --- Checagens --------------------------------------------------------------

# variavel de resultado geral (1 = tudo ok, 0 = alguma falha)
overall_ok=1

# check_nginx: faz uma requisicao HTTP real e avalia a resposta
check_nginx() {
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' -m "$HTTP_TIMEOUT" "$HEALTH_URL")"

    # codigo "000" significa que o curl nao obteve resposta nenhuma
    if [ "$code" = "000" ]; then
        overall_ok=0
        alert "nginx" "down"
        log "FAIL" "nginx nao responde (HTTP=$code)"
    else
        alert "nginx" "up"
        log "OK" "nginx respondendo (HTTP=$code)"
    fi
}

# check_php_fpm: verifica o socket e sonda o caminho PHP em busca de 502/504
check_php_fpm() {
    local problems=""

    # 1) o socket do PHP-FPM existe?
    [ -S "$PHP_FPM_SOCKET" ] || problems="socket ausente; "

    # 2) a requisicao PHP retorna erro de backend? (502/504 = FPM caido/lento)
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' -m "$HTTP_TIMEOUT" "$HEALTH_URL")"
    case "$code" in
        502|504|000) problems="${problems}PHP nao processa (HTTP=$code); " ;;
    esac

    # avalia o resultado
    if [ -n "$problems" ]; then
        overall_ok=0
        alert "php-fpm" "down"
        log "FAIL" "php-fpm com falha: $problems"
    else
        alert "php-fpm" "up"
        log "OK" "php-fpm respondendo (HTTP=$code)"
    fi
}

# --- Trava de execucao (evita sobreposicao no cron) -------------------------
exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
    flock -n 9 || { echo "$(ts) execucao ja em andamento, saindo."; exit 0; }
fi

# --- Preparacao --------------------------------------------------------------
mkdir -p "$STATE_DIR"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/health_check.log"

# --- Execucao ----------------------------------------------------------------
log "INFO" "--- iniciando verificacao ---"
check_nginx
check_php_fpm

if [ "$overall_ok" -eq 1 ]; then
    log "INFO" "resultado: TODOS OS SERVICOS OK"
    exit 0
else
    log "INFO" "resultado: FALHA DETECTADA"
    exit 1
fi