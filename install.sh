#!/bin/bash

# =============================================================================
# Гэл — установка на VPS одной командой
# =============================================================================
# Личный ИИ-секретарь в Telegram: голосовые, заметки, отчёты по встречам.
#
# Запуск (можно и нужно от root — так хостер обычно и выдаёт сервер):
#   bash <(curl -fsSL https://raw.githubusercontent.com/AlekdandrDG/Gaal_Secretar/main/install.sh)
#
# Скрипт сам подготовит сервер, сам создаст пользователя, сам переключится
# на него и доведёт установку до конца. Перезагрузка не нужна,
# второго шага нет.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Константы
# -----------------------------------------------------------------------------
UPSTREAM_USER="AlekdandrDG"
REPO_NAME="Gaal_Secretar"
REPO_URL="https://github.com/${UPSTREAM_USER}/${REPO_NAME}.git"

# Отсюда установщик перекачивает сам себя, когда его запустили потоком
# (`bash <(curl ...)` или `curl | bash`) и копировать нечего.
INSTALLER_URL="https://raw.githubusercontent.com/${UPSTREAM_USER}/${REPO_NAME}/main/install.sh"

DEFAULT_USER="gaal"

# Куда root кладёт копию скрипта, чтобы её мог прочитать целевой юзер.
# Именно файл, а не поток: `bash <(curl ...)` даёт временный дескриптор,
# который после смены пользователя уже не открыть.
SELF_COPY="/usr/local/lib/gaal-install.sh"

# Лог. От root пишем в /var/log, от обычного юзера — к нему в домашнюю.
if [ "$(id -u)" -eq 0 ]; then
    LOG_FILE="/var/log/gaal-install.log"
else
    LOG_FILE="$HOME/gaal-install.log"
fi

# -----------------------------------------------------------------------------
# Оформление
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

info()    { echo -e "${BLUE}[*]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[X]${NC} $1"; }
ask()     { echo -e "${YELLOW}?${NC} $1"; }

step() {
    CURRENT_STEP="$1"
    echo ""
    echo -e "${CYAN}${BOLD}--> $1${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
}

print_banner() {
    echo ""
    echo -e "${PURPLE}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════╗"
    echo "  ║                                                           ║"
    echo "  ║                  ГЭЛ — УСТАНОВКА НА VPS                   ║"
    echo "  ║                                                           ║"
    echo "  ║      Личный ИИ-секретарь с долговременной памятью         ║"
    echo "  ║                                                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Обработка сбоев
# -----------------------------------------------------------------------------
# Голый `set -e` роняет скрипт молча, и человек остаётся с пустым экраном.
# Ловим и объясняем: на каком шаге упало и что показать в поддержку.
CURRENT_STEP="запуск"

on_error() {
    local exit_code=$1
    local line=$2
    echo ""
    error "Установка прервалась на шаге: ${CURRENT_STEP}"
    echo "  (строка ${line}, код выхода ${exit_code})"
    echo ""
    echo "  Что делать:"
    echo "    1. Запустите установщик ещё раз — он продолжит с места обрыва,"
    echo "       уже сделанное не будет переделываться."
    echo "    2. Если повторяется — пришлите лог установки:"
    echo -e "       ${CYAN}cat ${LOG_FILE}${NC}"
    echo ""
    exit "$exit_code"
}
trap 'on_error $? $LINENO' ERR

# -----------------------------------------------------------------------------
# Утилиты
# -----------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# Единая точка «выполнить с правами root»: под root — напрямую,
# под обычным юзером — через sudo.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Ключи почти всегда копируют мышкой, и вместе с ними приезжают пробелы,
# переносы строк и невидимые символы. Чистим до проверки — иначе человек
# видит «неверный формат» на визуально правильном ключе.
trim_key() { printf '%s' "$1" | tr -d '[:space:]'; }

# =============================================================================
# ВАЛИДАЦИЯ КЛЮЧЕЙ
# =============================================================================
# Каждая проверка объясняет, ЧТО не так: длина, символы или структура.
# Молчаливое «неверный формат» заставляет гадать.

validate_telegram_token() {
    local token="$1"
    local len=${#token}

    # Формат: <id бота>:<секрет>, например 123456789:ABC-DEF1234ghIkl-zyx57W2v
    # Живые токены — около 45 символов, но Telegram границ не обещает,
    # поэтому проверяем с запасом.
    if [[ ! $token =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
        if [[ $token != *:* ]]; then
            error "В токене нет двоеточия. Должно быть вида: 123456789:ABC-DEF..."
        else
            error "Недопустимые символы. Разрешены цифры, латиница, дефис и подчёркивание"
        fi
        return 1
    fi
    if [ "$len" -lt 35 ]; then
        error "Токен короткий: $len символов, ожидается около 45. Скопирован не полностью?"
        return 1
    fi
    if [ "$len" -gt 60 ]; then
        error "Токен длинный: $len символов, ожидается около 45. Прихвачено лишнее?"
        return 1
    fi
    return 0
}

validate_telegram_id() {
    local id="$1"
    local len=${#id}

    if [[ ! $id =~ ^[0-9]+$ ]]; then
        error "ID должен состоять только из цифр. Возьмите его у @userinfobot"
        return 1
    fi
    # ID пользователей Telegram — обычно 9-10 цифр.
    # Частая ошибка: вместо ID вставляют токен бота.
    if [ "$len" -lt 5 ]; then
        error "ID короткий: $len цифр, ожидается 9-10"
        return 1
    fi
    if [ "$len" -gt 12 ]; then
        error "ID длинный: $len цифр, ожидается 9-10. Возможно, вставлен токен вместо ID"
        return 1
    fi
    return 0
}

validate_alnum_key() {
    local key="$1" name="$2" expected="$3"
    local len=${#key}

    if [[ ! $key =~ ^[A-Za-z0-9]+$ ]]; then
        error "$name состоит только из букв и цифр — уберите лишние символы"
        return 1
    fi
    if [ "$len" -lt 30 ]; then
        error "$name короткий: $len символов, ожидается $expected. Скопирован не полностью?"
        return 1
    fi
    if [ "$len" -gt 50 ]; then
        error "$name длинный: $len символов, ожидается $expected. Прихвачено лишнее?"
        return 1
    fi
    return 0
}

# =============================================================================
# STAGE 1 — root-часть: система, пользователь, firewall
# =============================================================================

# На свежих VPS у некоторых хостеров DNS не настроен: система не может
# превратить имя сайта в адрес, и любая загрузка падает с
# «Could not resolve host». Проверяем и чиним до того, как что-то качать.
fix_dns() {
    step "Проверка доступа в интернет"

    if getent hosts github.com >/dev/null 2>&1; then
        success "Интернет доступен"
        return 0
    fi

    warn "Сервер не может разрешать доменные имена — настраиваю DNS"

    if [ "$(id -u)" -ne 0 ]; then
        error "Чтобы починить DNS, нужны права root"
        # shellcheck disable=SC2028  # это подсказка человеку: \n должен остаться текстом
        echo "  Выполните от root: printf 'nameserver 8.8.8.8\\nnameserver 1.1.1.1\\n' > /etc/resolv.conf"
        exit 1
    fi

    printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf

    if getent hosts github.com >/dev/null 2>&1; then
        success "DNS настроен"
    else
        error "DNS всё ещё не работает"
        echo "  Проверьте сетевые настройки сервера или обратитесь в поддержку хостинга."
        exit 1
    fi
}

check_os() {
    step "Проверка операционной системы"

    if [ ! -f /etc/os-release ]; then
        error "Не удалось определить операционную систему"
        echo "  Гэл рассчитана на Ubuntu 24.04."
        exit 1
    fi

    # shellcheck disable=SC1091  # файл появляется только на целевой машине
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-неизвестна}"

    if [ "$OS_ID" = "ubuntu" ]; then
        success "Ubuntu $OS_VERSION"
        return 0
    fi

    # Python 3.12 ставится из ppa:deadsnakes, а PPA — механизм Ubuntu.
    # На Debian и прочих он просто не подключится, и установка развалится
    # где-то в середине. Честнее сказать об этом сразу.
    error "Обнаружена система: ${OS_ID} ${OS_VERSION}"
    echo ""
    echo "  Гэл устанавливается только на Ubuntu (проверено на 24.04)."
    echo "  Причина: Python 3.12 берётся из репозитория ppa:deadsnakes,"
    echo "  который работает лишь в Ubuntu."
    echo ""
    echo "  Что делать: пересоздайте сервер с образом Ubuntu 24.04"
    echo "  в панели управления хостинга — это обычно занимает пару минут."
    echo ""
    exit 1
}

install_base_packages() {
    step "Обновление системы и базовые пакеты"

    export DEBIAN_FRONTEND=noninteractive

    info "Обновляю список пакетов..."
    as_root apt-get update -qq

    info "Устанавливаю базовые пакеты (git, curl, sudo, ufw и другие)..."
    as_root apt-get install -y -qq \
        git curl wget sudo ufw ca-certificates \
        build-essential software-properties-common

    success "Базовые пакеты установлены"
}

# Имя пользователя, под которым будет жить бот.
choose_user() {
    step "Пользователь для Гэл"

    echo ""
    echo "  Работать под root опасно: любая ошибка или взлом дают"
    echo "  злоумышленнику весь сервер целиком. Поэтому бот будет жить"
    echo "  под обычным пользователем — сейчас его создадим."
    echo ""
    echo "  Имя — латиницей, без пробелов."
    echo ""

    while true; do
        ask "Имя пользователя [Enter = ${DEFAULT_USER}]:"
        read -r GAAL_USER
        GAAL_USER=${GAAL_USER:-$DEFAULT_USER}

        if [[ ! "$GAAL_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            error "Только строчные латинские буквы, цифры, дефис и подчёркивание"
            continue
        fi
        break
    done
}

create_user() {
    step "Создание пользователя «${GAAL_USER}»"

    if id "$GAAL_USER" >/dev/null 2>&1; then
        # Повторный запуск или юзер был заведён раньше — это нормальный случай,
        # просто используем его.
        success "Пользователь «${GAAL_USER}» уже есть — использую его"
    else
        # Пароль не спрашиваем: вход на сервер идёт по SSH-ключу,
        # а команды root-уровня пойдут через NOPASSWD sudo.
        # Лишний пароль — лишний шаг, который люди теряют.
        as_root adduser --disabled-password --gecos "" "$GAAL_USER" >/dev/null
        success "Пользователь «${GAAL_USER}» создан (без пароля — вход по SSH-ключу)"
    fi

    GAAL_HOME=$(getent passwd "$GAAL_USER" | cut -d: -f6)
    if [ -z "$GAAL_HOME" ]; then
        error "Не удалось определить домашнюю директорию «${GAAL_USER}»"
        exit 1
    fi

    as_root usermod -aG sudo "$GAAL_USER"
    success "Права администратора выданы"
}

grant_nopasswd_sudo() {
    step "Настройка sudo без пароля"

    local sudoers_file="/etc/sudoers.d/${GAAL_USER}"

    if [ -f "$sudoers_file" ] && as_root grep -q "^${GAAL_USER} ALL=(ALL) NOPASSWD:ALL$" "$sudoers_file" 2>/dev/null; then
        success "Уже настроено"
        return 0
    fi

    # У пользователя нет пароля, значит обычный sudo его никогда не пропустит.
    # Пишем правило через временный файл и проверяем visudo ДО установки:
    # битый файл в /etc/sudoers.d ломает sudo на всей машине целиком.
    local tmp_sudoers
    tmp_sudoers=$(mktemp)
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$GAAL_USER" > "$tmp_sudoers"

    if ! as_root visudo -c -f "$tmp_sudoers" >/dev/null 2>&1; then
        rm -f "$tmp_sudoers"
        error "Проверка правила sudo не прошла — не рискую менять настройки"
        exit 1
    fi

    as_root install -m 0440 -o root -g root "$tmp_sudoers" "$sudoers_file"
    rm -f "$tmp_sudoers"

    success "«${GAAL_USER}» может выполнять администраторские команды без пароля"
}

copy_ssh_keys() {
    step "Доступ по SSH для «${GAAL_USER}»"

    local root_keys="/root/.ssh/authorized_keys"

    if [ ! -s "$root_keys" ]; then
        # Не блокируем установку: боту SSH-доступ пользователя не нужен,
        # он запускается systemd. Но человека предупредить обязаны.
        warn "У root нет SSH-ключей — копировать нечего"
        echo ""
        echo "  Это значит: войти на сервер под «${GAAL_USER}» по SSH вы не сможете."
        echo "  Заходите как обычно — под root, установке и работе бота это не мешает."
        echo ""
        echo "  Если позже захотите заходить под «${GAAL_USER}», добавьте свой"
        echo "  публичный ключ в ${GAAL_HOME}/.ssh/authorized_keys"
        echo ""
        return 0
    fi

    as_root mkdir -p "${GAAL_HOME}/.ssh"
    as_root cp "$root_keys" "${GAAL_HOME}/.ssh/authorized_keys"
    as_root chown -R "${GAAL_USER}:${GAAL_USER}" "${GAAL_HOME}/.ssh"
    as_root chmod 700 "${GAAL_HOME}/.ssh"
    as_root chmod 600 "${GAAL_HOME}/.ssh/authorized_keys"

    success "SSH-ключи скопированы — сможете заходить как ${GAAL_USER}@сервер"
}

# Порты, на которых слушает SSH.
#
# Цена ошибки здесь максимальная: включить firewall, не разрешив реальный
# порт, — значит запереть человека снаружи собственного сервера, и откатить
# это будет некому. Поэтому собираем порты из трёх источников и разрешаем
# всё найденное.
detect_ssh_ports() {
    local ports=""

    # 1. Самый достоверный источник — порт текущей сессии. Если мы сюда
    # попали по SSH, этот порт заведомо рабочий.
    # Формат SSH_CONNECTION: <client ip> <client port> <server ip> <server port>
    if [ -n "${SSH_CONNECTION:-}" ]; then
        local from_session
        from_session=$(awk '{print $4}' <<< "$SSH_CONNECTION" 2>/dev/null || echo "")
        if [[ "$from_session" =~ ^[0-9]+$ ]]; then
            ports="$from_session"
        fi
    fi

    # 2. Директива Port из конфигов sshd. Учитываем и sshd_config.d/*.conf —
    # многие хостеры меняют порт именно там, не трогая основной файл.
    local cfg
    for cfg in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$cfg" ] || continue
        # Строки вида "Port 2222" — без комментариев, с любым отступом.
        local found
        found=$(grep -iE '^[[:space:]]*Port[[:space:]]+[0-9]+' "$cfg" 2>/dev/null \
                | awk '{print $2}' || true)
        local p
        for p in $found; do
            [[ "$p" =~ ^[0-9]+$ ]] && ports="$ports $p"
        done
    done

    # 3. Что реально слушает sshd прямо сейчас.
    if have ss; then
        local listening
        listening=$(ss -tlnp 2>/dev/null | grep sshd 2>/dev/null \
                    | grep -oE ':[0-9]+' | tr -d ':' || true)
        local p
        for p in $listening; do
            [[ "$p" =~ ^[0-9]+$ ]] && ports="$ports $p"
        done
    fi

    # Уникализируем, сохраняя только осмысленные номера портов
    local uniq="" p
    for p in $ports; do
        if [ "$p" -ge 1 ] && [ "$p" -le 65535 ] 2>/dev/null; then
            [[ " $uniq " == *" $p "* ]] || uniq="$uniq $p"
        fi
    done

    # xargs схлопывает лишние пробелы
    echo "$uniq" | xargs 2>/dev/null || true
}

configure_firewall() {
    step "Firewall и автообновления безопасности"

    local ssh_ports
    ssh_ports=$(detect_ssh_ports)

    # Порядок важен: сначала разрешаем SSH, только потом включаем ufw.
    # Иначе можно закрыть себе доступ к серверу, на котором работаешь.
    as_root ufw default deny incoming >/dev/null
    as_root ufw default allow outgoing >/dev/null

    if [ -n "$ssh_ports" ]; then
        local p
        for p in $ssh_ports; do
            as_root ufw allow "${p}/tcp" >/dev/null
            info "Разрешён вход по SSH на порт ${p}"
        done
    else
        # Порт определить не удалось. Разрешаем стандартный 22 и говорим
        # об этом прямо: если сервер слушает другой порт, человек должен
        # успеть вмешаться до того, как потеряет доступ.
        as_root ufw allow 22/tcp >/dev/null
        echo ""
        warn "Не удалось определить порт SSH — разрешаю стандартный 22"
        echo ""
        echo "  Если вы подключаетесь к серверу по НЕстандартному порту,"
        echo "  firewall может закрыть вам доступ после включения."
        echo ""
        echo "  Проверьте порт в адресной строке SSH-клиента. Если он не 22 —"
        echo "  ответьте «n», разрешите свой порт вручную командой"
        echo "    sudo ufw allow ВАШ_ПОРТ/tcp"
        echo "  и запустите установщик заново."
        echo ""
        ask "Порт 22 — верный? Включаем firewall? (Y/n):"
        read -r fw_reply
        if [[ $fw_reply =~ ^[Nn]$ ]]; then
            warn "Firewall не включён — установка продолжается"
            echo "  Включить позже: sudo ufw allow ВАШ_ПОРТ/tcp && sudo ufw --force enable"
            return 0
        fi
    fi

    as_root ufw --force enable >/dev/null
    success "Firewall включён — снаружи открыт только SSH"

    info "Включаю автоматические обновления безопасности..."
    as_root apt-get install -y -qq unattended-upgrades >/dev/null 2>&1 || true
    printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
        | as_root tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
    success "Автообновления включены"
}

# Переключение на целевого пользователя без перезагрузки и без разрыва сессии.
switch_to_user() {
    step "Переключаюсь на пользователя «${GAAL_USER}»"

    # Целевому юзеру нужен обычный файл со скриптом.
    #
    # Тонкость: при запуске `bash <(curl ...)` — а это основной способ из
    # README — $0 равен /dev/fd/N. Такой «файл» читается, но не копируется:
    # install падает с «Inappropriate file type or format». Поэтому проверка
    # именно -f (обычный файл), а не -r (читаемый) — -r здесь даёт ложную
    # уверенность. То же и при `curl | bash`, где $0 вообще не файл.
    #
    # Порядок: обычный файл — копируем; иначе скачиваем заново по known URL
    # (репозиторий публичный, токен не нужен).
    # ${BASH_SOURCE[0]:-} с дефолтом: при `curl | bash` переменная вообще
    # не определена, и без дефолта set -u убил бы скрипт прямо здесь.
    local self_path="${BASH_SOURCE[0]:-}"

    if [ -n "$self_path" ] && [ -f "$self_path" ]; then
        as_root install -m 0755 -o root -g root "$self_path" "$SELF_COPY"
    else
        info "Скачиваю установщик для второй части..."

        local tmp_self
        tmp_self=$(mktemp)

        if ! curl -fsSL "$INSTALLER_URL" -o "$tmp_self"; then
            rm -f "$tmp_self"
            error "Не удалось скачать установщик с GitHub"
            echo "  Проверьте интернет на сервере: curl -I https://github.com"
            echo "  Адрес: $INSTALLER_URL"
            exit 1
        fi

        # Проверяем, что скачался именно скрипт, а не страница ошибки
        # или пустой файл: иначе su запустит мусор и всё развалится
        # с непонятным сообщением.
        if [ ! -s "$tmp_self" ]; then
            rm -f "$tmp_self"
            error "Скачанный файл установщика пуст"
            echo "  Попробуйте ещё раз: возможно, GitHub был временно недоступен."
            exit 1
        fi

        if ! head -n 1 "$tmp_self" | grep -q '^#!.*sh'; then
            rm -f "$tmp_self"
            error "Скачался не скрипт установки"
            echo "  Вероятно, GitHub вернул страницу с ошибкой."
            echo "  Проверьте вручную: curl -I $INSTALLER_URL"
            exit 1
        fi

        as_root install -m 0755 -o root -g root "$tmp_self" "$SELF_COPY"
        rm -f "$tmp_self"
    fi

    if [ ! -s "$SELF_COPY" ]; then
        error "Не удалось подготовить установщик для второй части"
        exit 1
    fi

    echo ""
    echo "  Root-часть готова. Дальше установка продолжится"
    echo "  от имени «${GAAL_USER}» — прямо здесь, без перезагрузки."
    echo ""

    # exec, а не пайп и не подстановка: процесс заменяется целиком,
    # stdin остаётся тем же терминалом — иначе `read` не сможет
    # задавать вопросы и установка встанет.
    exec su - "$GAAL_USER" -c "GAAL_STAGE=2 GAAL_INSTALL_USER='${GAAL_USER}' bash '${SELF_COPY}' --stage2"
}

# =============================================================================
# STAGE 2 — установка от имени пользователя
# =============================================================================

install_python() {
    step "Python 3.12"

    if have python3.12; then
        success "Python 3.12 уже установлен: $(python3.12 --version 2>&1)"
        return 0
    fi

    info "Подключаю репозиторий deadsnakes..."
    export DEBIAN_FRONTEND=noninteractive
    as_root add-apt-repository -y ppa:deadsnakes/ppa >/dev/null
    as_root apt-get update -qq

    info "Устанавливаю Python 3.12..."
    as_root apt-get install -y -qq python3.12 python3.12-venv python3.12-dev

    if ! have python3.12; then
        error "Python 3.12 не установился"
        echo "  Проверьте вручную: sudo apt-get install python3.12"
        exit 1
    fi

    success "Python 3.12 установлен"
}

install_nodejs() {
    step "Node.js 20"

    if have node; then
        local major
        major=$(node --version | sed 's/^v//' | cut -d. -f1)
        if [ "$major" -ge 18 ] 2>/dev/null; then
            success "Node.js $(node --version) уже установлен"
            return 0
        fi
        warn "Установлен Node.js $(node --version) — слишком старый, обновляю"
    fi

    info "Подключаю репозиторий NodeSource..."
    # Скрипт NodeSource читаем во временный файл, а не гоним по пайпу в sudo:
    # `sudo bash -` работает, а от root тот же пайп ведёт себя иначе,
    # и флаги sudo туда подмешивать нельзя.
    local ns_script
    ns_script=$(mktemp)
    curl -fsSL https://deb.nodesource.com/setup_20.x -o "$ns_script"
    as_root env DEBIAN_FRONTEND=noninteractive bash "$ns_script" >/dev/null
    rm -f "$ns_script"

    info "Устанавливаю Node.js..."
    as_root apt-get install -y -qq nodejs

    success "Node.js $(node --version) установлен"
}

install_claude_cli() {
    step "Claude CLI"

    if have claude; then
        success "Claude CLI уже установлен"
        return 0
    fi

    info "Устанавливаю @anthropic-ai/claude-code..."
    as_root npm install -g @anthropic-ai/claude-code >/dev/null

    if ! have claude; then
        error "Claude CLI не установился"
        echo "  Проверьте вручную: sudo npm install -g @anthropic-ai/claude-code"
        exit 1
    fi

    success "Claude CLI установлен"
}

install_uv() {
    step "uv — менеджер зависимостей Python"

    UV_BIN="$HOME/.local/bin/uv"

    if [ -x "$UV_BIN" ]; then
        success "uv уже установлен: $("$UV_BIN" --version 2>&1)"
    elif have uv; then
        UV_BIN=$(command -v uv)
        success "uv уже установлен: $(uv --version 2>&1)"
    else
        info "Скачиваю и устанавливаю uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null

        if [ ! -x "$UV_BIN" ]; then
            error "uv не установился"
            echo "  Проверьте вручную: curl -LsSf https://astral.sh/uv/install.sh | sh"
            exit 1
        fi
        success "uv установлен"
    fi

    export PATH="$HOME/.local/bin:$PATH"

    # Чтобы uv был под рукой и при следующем входе на сервер.
    # Кавычки одинарные намеренно: в .bashrc должна попасть строка с
    # буквальным $HOME, который раскроется при входе, а не сейчас.
    # shellcheck disable=SC2016
    if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
}

clone_repository() {
    step "Загрузка Гэл"

    PROJECT_DIR="$HOME/$REPO_NAME"

    if [ -d "$PROJECT_DIR/.git" ]; then
        # Повторный запуск. Не сносим и не переклонируем: в директории
        # уже могут лежать .env, хранилище мыслей и ключи Google.
        success "Гэл уже загружена в $PROJECT_DIR"
        info "Проверяю обновления..."
        if git -C "$PROJECT_DIR" pull --ff-only >/dev/null 2>&1; then
            success "Код обновлён до последней версии"
        else
            warn "Обновить не удалось — работаю с той версией, что есть"
        fi
        return 0
    fi

    if [ -e "$PROJECT_DIR" ]; then
        error "По пути $PROJECT_DIR уже что-то лежит, но это не репозиторий Гэл"
        echo "  Переименуйте или удалите эту директорию и запустите установщик снова."
        exit 1
    fi

    info "Загружаю из $REPO_URL ..."
    if ! git clone --quiet "$REPO_URL" "$PROJECT_DIR"; then
        error "Не удалось загрузить Гэл с GitHub"
        echo "  Проверьте интернет на сервере: curl -I https://github.com"
        exit 1
    fi

    success "Гэл загружена в $PROJECT_DIR"
}

# -----------------------------------------------------------------------------
# Ключи
# -----------------------------------------------------------------------------

collect_tokens() {
    step "Ключи доступа"

    echo ""
    echo "  Сейчас понадобятся четыре ключа. Если ещё не получили —"
    echo "  инструкции лежат в docs/ этого репозитория."
    echo ""
    echo "    1. Токен бота Telegram — у @BotFather"
    echo "    2. Ваш ID в Telegram   — у @userinfobot"
    echo "    3. Ключ Deepgram       — console.deepgram.com"
    echo "    4. Токен Todoist       — Настройки > Интеграции > Разработчик"
    echo ""

    # Telegram Bot Token.
    # Проверяем не только формат, но и живость: отозванный или чужой токен
    # выглядит правильно, а бот с ним не стартует — и выясняется это
    # уже в самом конце установки.
    while true; do
        ask "Токен бота Telegram:"
        read -r TELEGRAM_BOT_TOKEN
        TELEGRAM_BOT_TOKEN=$(trim_key "$TELEGRAM_BOT_TOKEN")

        if ! validate_telegram_token "$TELEGRAM_BOT_TOKEN"; then
            continue
        fi

        info "Проверяю токен у Telegram..."
        local tg_response
        tg_response=$(curl -s --max-time 15 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null) || tg_response=""

        if echo "$tg_response" | grep -q '"ok":true'; then
            local bot_name
            bot_name=$(echo "$tg_response" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
            success "Токен подошёл — бот @${bot_name:-неизвестен}"
            break
        elif [ -z "$tg_response" ]; then
            warn "Не удалось связаться с Telegram — проверьте интернет на сервере"
            ask "Продолжить с этим токеном? (y/N):"
            read -r reply
            [[ $reply =~ ^[Yy]$ ]] && break
        else
            error "Telegram отклонил токен"
            echo "  Возможные причины: токен отозван, бот удалён, скопирован не полностью."
            echo "  Возьмите актуальный: @BotFather → /mybots → ваш бот → API Token"
        fi
    done

    # Telegram User ID
    while true; do
        ask "Ваш ID в Telegram (у @userinfobot):"
        read -r TELEGRAM_USER_ID
        TELEGRAM_USER_ID=$(trim_key "$TELEGRAM_USER_ID")
        if validate_telegram_id "$TELEGRAM_USER_ID"; then
            success "ID принят"
            break
        fi
    done

    # Deepgram — расшифровка голосовых, без него голосовые не работают.
    while true; do
        ask "Ключ Deepgram (console.deepgram.com):"
        read -r DEEPGRAM_API_KEY
        DEEPGRAM_API_KEY=$(trim_key "$DEEPGRAM_API_KEY")
        if validate_alnum_key "$DEEPGRAM_API_KEY" "Ключ Deepgram" "40"; then
            success "Ключ принят"
            break
        fi
    done

    # Todoist — постановка задач.
    while true; do
        ask "Токен Todoist (Настройки > Интеграции > Разработчик):"
        read -r TODOIST_API_KEY
        TODOIST_API_KEY=$(trim_key "$TODOIST_API_KEY")
        if validate_alnum_key "$TODOIST_API_KEY" "Токен Todoist" "40"; then
            success "Токен принят"
            break
        fi
    done
}

# Часовой пояс: сервер обычно в UTC, а напоминания должны приходить
# по местному времени. Без этого вечерний дайджест в 21:00
# прилетит среди ночи. Один вопрос — стоит того.
collect_timezone() {
    step "Часовой пояс"

    echo ""
    echo "  По нему приходят напоминания и вечерние отчёты."
    echo ""
    echo "    1) Europe/Moscow      — Москва, Санкт-Петербург (UTC+3)"
    echo "    2) Europe/Kaliningrad — Калининград (UTC+2)"
    echo "    3) Asia/Yekaterinburg — Екатеринбург (UTC+5)"
    echo "    4) Asia/Novosibirsk   — Новосибирск (UTC+7)"
    echo "    5) Asia/Vladivostok   — Владивосток (UTC+10)"
    echo "    6) Asia/Almaty        — Алматы, Астана (UTC+5)"
    echo "    7) Asia/Tashkent      — Ташкент (UTC+5)"
    echo "    8) Europe/Minsk       — Минск (UTC+3)"
    echo "    9) другой — ввести вручную"
    echo ""

    while true; do
        ask "Ваш часовой пояс [1-9, Enter = 1]:"
        read -r tz_choice
        tz_choice=${tz_choice:-1}

        case "$tz_choice" in
            1) BOT_TIMEZONE="Europe/Moscow" ;;
            2) BOT_TIMEZONE="Europe/Kaliningrad" ;;
            3) BOT_TIMEZONE="Asia/Yekaterinburg" ;;
            4) BOT_TIMEZONE="Asia/Novosibirsk" ;;
            5) BOT_TIMEZONE="Asia/Vladivostok" ;;
            6) BOT_TIMEZONE="Asia/Almaty" ;;
            7) BOT_TIMEZONE="Asia/Tashkent" ;;
            8) BOT_TIMEZONE="Europe/Minsk" ;;
            9)
                echo "  Формат: Континент/Город, например Europe/Berlin или America/New_York"
                echo "  Полный список: timedatectl list-timezones"
                ask "Часовой пояс:"
                read -r BOT_TIMEZONE
                ;;
            *)
                error "Введите число от 1 до 9"
                continue
                ;;
        esac

        if [ -f "/usr/share/zoneinfo/$BOT_TIMEZONE" ]; then
            success "Часовой пояс: $BOT_TIMEZONE"
            break
        fi
        error "Часовой пояс «$BOT_TIMEZONE» не найден. Проверьте написание."
    done
}

create_env_file() {
    step "Файл настроек .env"

    ENV_FILE="$PROJECT_DIR/.env"

    # Если .env уже есть (повторный запуск, ручная правка) — не затираем молча:
    # там могут лежать токен Claude и настройки Google, полученные с трудом.
    if [ -f "$ENV_FILE" ]; then
        warn "Файл настроек уже существует: $ENV_FILE"
        echo ""
        echo "  1) Оставить как есть — ничего не спрашивать (по умолчанию)"
        echo "  2) Ввести ключи заново и перезаписать"
        echo ""
        ask "Что делаем? [1/2, Enter = 1]:"
        read -r env_choice

        if [ "${env_choice:-1}" != "2" ]; then
            success "Оставляю существующие настройки"
            return 0
        fi

        # Сохраняем копию: если человек ошибётся, старые ключи не пропадут.
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        warn "Старый файл сохранён рядом с пометкой .backup"
    fi

    collect_tokens
    collect_timezone

    # Страховка: пустой TZ в .env перебил бы разумный умолчательный UTC
    # в scripts/process.sh. Сюда попасть не должны — collect_timezone
    # проверяет зону по /usr/share/zoneinfo, — но цена опечатки высока.
    if [ -z "${BOT_TIMEZONE:-}" ]; then
        BOT_TIMEZONE="UTC"
        warn "Часовой пояс не определился — записываю UTC"
    fi

    cat > "$ENV_FILE" << EOF
# ── Обязательные ключи ────────────────────────────────────────────

# Токен бота Telegram (от @BotFather)
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}

# Ключ Deepgram — расшифровка голосовых
DEEPGRAM_API_KEY=${DEEPGRAM_API_KEY}

# Токен Todoist — задачи
TODOIST_API_KEY=${TODOIST_API_KEY}

# Кому разрешено писать боту. Это единственная защита:
# пустой список = бот никого не пускает.
ALLOWED_USER_IDS=[${TELEGRAM_USER_ID}]

# Путь к хранилищу мыслей
VAULT_PATH=./vault

# Часовой пояс — по нему приходят напоминания и отчёты
TZ=${BOT_TIMEZONE}

# ── Опционально: Google Calendar ──────────────────────────────────
# Без этого бот работает, просто не пишет встречи и билеты в календарь.
# Как подключить: docs/google-setup.md
# Коротко: положить service account JSON в data/secrets/google-credentials.json
# и перезапустить бота: sudo systemctl restart d-brain-bot

GOOGLE_CREDENTIALS_PATH=data/secrets/google-credentials.json

# В какой календарь писать события.
# ВАЖНО: строка намеренно закомментирована. Пустое значение здесь —
# это не «не задано»: бот прочитает пустую строку и потеряет разумный
# умолчательный календарь (primary). Чтобы указать свой — раскомментируйте
# и впишите адрес календаря, к которому открыт доступ service account'у.
# GOOGLE_CALENDAR_ID=example@gmail.com

# ── Опционально ───────────────────────────────────────────────────

# Путь к claude, если его нет в PATH.
# Тоже закомментировано намеренно: пустое значение перебило бы
# автоматический поиск claude в PATH.
# CLAUDE_BIN=/usr/bin/claude
EOF

    chmod 600 "$ENV_FILE"
    success "Настройки сохранены (права 600 — читать может только вы)"
}

install_dependencies() {
    step "Зависимости Python"

    info "Выполняю uv sync — это может занять пару минут..."
    (cd "$PROJECT_DIR" && "$UV_BIN" sync >/dev/null)

    success "Зависимости установлены"
}

# -----------------------------------------------------------------------------
# systemd
# -----------------------------------------------------------------------------
# В репозитории лежат готовые шаблоны юнитов с плейсхолдерами.
# Ставим все, а не только бота: без таймеров не будет ни вечерней
# обработки, ни недельного дайджеста — то есть половины смысла.
install_systemd_units() {
    step "Автозапуск и расписание (systemd)"

    local deploy_dir="$PROJECT_DIR/deploy"

    if [ ! -d "$deploy_dir" ]; then
        error "В репозитории нет директории deploy/ — нечего устанавливать"
        exit 1
    fi

    local unit
    for unit in d-brain-bot.service d-brain-process.service d-brain-weekly.service d-brain-notify@.service; do
        if [ ! -f "$deploy_dir/$unit" ]; then
            warn "Шаблон $unit не найден — пропускаю"
            continue
        fi
        sed -e "s|__USER__|${GAAL_USER}|g" \
            -e "s|__HOME__|${HOME}|g" \
            -e "s|__PROJECT_DIR__|${PROJECT_DIR}|g" \
            -e "s|__UV_BIN__|${UV_BIN}|g" \
            "$deploy_dir/$unit" \
          | as_root tee "/etc/systemd/system/$unit" >/dev/null
        info "Установлен $unit"
    done

    local timer
    for timer in d-brain-process.timer d-brain-weekly.timer; do
        if [ ! -f "$deploy_dir/$timer" ]; then
            warn "Таймер $timer не найден — пропускаю"
            continue
        fi
        as_root cp "$deploy_dir/$timer" "/etc/systemd/system/$timer"
        info "Установлен $timer"
    done

    # Drop-in OnFailure=: если юнит упал, бот сам напишет об этом в Telegram.
    # Кладём только тем юнитам, что реально установлены.
    if [ -f "$deploy_dir/dropins/onfailure.conf" ]; then
        local target
        for target in d-brain-bot.service d-brain-process.service d-brain-weekly.service; do
            [ -f "/etc/systemd/system/$target" ] || continue
            as_root mkdir -p "/etc/systemd/system/${target}.d"
            as_root cp "$deploy_dir/dropins/onfailure.conf" \
                "/etc/systemd/system/${target}.d/onfailure.conf"
        done
        success "Оповещения о сбоях подключены"
    fi

    # Скрипты, на которые ссылаются юниты, должны быть исполняемыми —
    # после git clone права иногда теряются.
    local script
    for script in "$PROJECT_DIR/scripts/process.sh" "$PROJECT_DIR/scripts/notify.sh"; do
        [ -f "$script" ] && chmod +x "$script"
    done

    as_root systemctl daemon-reload

    info "Включаю автозапуск бота..."
    as_root systemctl enable --now d-brain-bot.service >/dev/null 2>&1 || {
        warn "Бот не стартовал с первого раза — разберёмся в конце"
    }

    local t
    for t in d-brain-process.timer d-brain-weekly.timer; do
        [ -f "/etc/systemd/system/$t" ] || continue
        if as_root systemctl enable --now "$t" >/dev/null 2>&1; then
            info "Расписание $t включено"
        else
            warn "Не удалось включить $t"
        fi
    done

    success "Автозапуск настроен: бот, вечерняя обработка (21:00), дайджест (пятница 06:00)"
}

# Claude — «мозги» бота. Без авторизации бот запустится, но на любой
# запрос будет отвечать ошибкой «Not logged in».
#
# На сервере нет браузера, поэтому вход идёт через `claude setup-token`:
# команда печатает ссылку, пользователь открывает её у себя на компьютере,
# получает код и возвращает его сюда. На выходе — токен, который мы
# сохраняем в .env (systemd читает этот файл как окружение сервиса).
#
# ВАЖНО: выполняется от имени целевого юзера (мы уже в stage 2),
# иначе сессия Claude легла бы в /root и бот её не увидел.
authorize_claude() {
    step "Авторизация Claude"

    if [ "$(id -u)" -eq 0 ]; then
        # Страховка: сюда мы попадать не должны.
        warn "Авторизация от root пропущена — токен лёг бы не туда"
        return 0
    fi

    if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
        success "Claude уже авторизован"
        return 0
    fi

    if grep -q '^CLAUDE_CODE_OAUTH_TOKEN=.\+' "$ENV_FILE" 2>/dev/null; then
        success "Токен Claude уже сохранён в настройках"
        return 0
    fi

    echo ""
    echo "  Claude — это «мозги» Гэл. Без него бот запустится,"
    echo "  но не сможет обрабатывать заметки и отвечать осмысленно."
    echo ""
    echo "  Нужна активная подписка Claude (Pro или Max)."
    echo ""
    echo -e "  ${YELLOW}Как это будет:${NC}"
    echo "    1. Сейчас запустится команда авторизации"
    echo "    2. Она напечатает ссылку — откройте её в браузере"
    echo "       на своём компьютере (не на сервере)"
    echo "    3. Войдите в аккаунт Claude и подтвердите доступ"
    echo "    4. Скопируйте код обратно сюда"
    echo ""
    echo -e "  ${RED}ВАЖНО:${NC} на экране появится токен доступа к вашей подписке."
    echo "  Не показывайте экран посторонним и не ведите трансляцию."
    echo ""

    ask "Авторизоваться сейчас? (Y/n):"
    read -r reply
    if [[ $reply =~ ^[Nn]$ ]]; then
        warn "Авторизация пропущена — бот пока не сможет думать"
        echo "  Сделать позже: claude setup-token"
        echo "  Затем вписать полученный токен в ${ENV_FILE} строкой:"
        echo "    CLAUDE_CODE_OAUTH_TOKEN=<токен>"
        echo "  И перезапустить: sudo systemctl restart d-brain-bot"
        return 0
    fi

    echo ""
    local token_out
    token_out=$(claude setup-token 2>&1 | tee /dev/tty) || true

    # Достаём токен из вывода: он начинается с sk-ant- и может быть
    # разбит переносами строк, поэтому склеиваем.
    local claude_token
    claude_token=$(echo "$token_out" | tr -d ' \n' | grep -o 'sk-ant-[A-Za-z0-9_-]\+' | head -1) || claude_token=""

    if [ -z "$claude_token" ]; then
        echo ""
        warn "Не удалось распознать токен автоматически"
        echo "  Если токен всё же был выдан — скопируйте его и вставьте ниже."
        echo "  Или нажмите Enter, чтобы пропустить."
        echo ""
        ask "Токен Claude:"
        read -r claude_token
        claude_token=$(trim_key "$claude_token")
    fi

    if [ -z "$claude_token" ]; then
        warn "Авторизация не завершена — бот пока не сможет думать"
        echo "  Сделать позже: claude setup-token"
        return 0
    fi

    sed -i '/^CLAUDE_CODE_OAUTH_TOKEN=/d' "$ENV_FILE"
    printf '\n# Токен доступа к подписке Claude\nCLAUDE_CODE_OAUTH_TOKEN=%s\n' "$claude_token" >> "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    echo ""
    success "Токен Claude сохранён"

    as_root systemctl restart d-brain-bot >/dev/null 2>&1 || true
    success "Бот перезапущен с новым токеном"
}

# -----------------------------------------------------------------------------
# Финальная проверка
# -----------------------------------------------------------------------------
final_check() {
    step "Проверка"

    echo ""
    if have python3.12; then success "Python 3.12: $(python3.12 --version 2>&1)"; else error "Python 3.12 не найден"; fi
    if [ -x "$UV_BIN" ]; then success "uv: $("$UV_BIN" --version 2>&1)"; else error "uv не найден"; fi
    if have node; then success "Node.js: $(node --version)"; else error "Node.js не найден"; fi
    if have claude; then success "Claude CLI: установлен"; else error "Claude CLI не найден"; fi
    if [ -f "$ENV_FILE" ]; then success "Файл настроек: на месте"; else error "Файл настроек не найден"; fi

    # Сервису нужно время подняться после enable --now / restart
    sleep 3

    if systemctl is-active --quiet d-brain-bot; then
        success "Бот: работает"
        echo ""
        echo -e "${GREEN}${BOLD}"
        echo "  ╔═══════════════════════════════════════════════════════════╗"
        echo "  ║                                                           ║"
        echo "  ║                   ГЭЛ УСТАНОВЛЕНА                         ║"
        echo "  ║                                                           ║"
        echo "  ╚═══════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo "  Что дальше:"
        echo "    1. Откройте Telegram и найдите своего бота"
        echo "    2. Отправьте /start"
        echo "    3. Запишите голосовое — Гэл разберёт его сама"
        echo ""
        echo "  Полезные команды:"
        echo "    посмотреть журнал:  sudo journalctl -u d-brain-bot -f"
        echo "    перезапустить:      sudo systemctl restart d-brain-bot"
        echo "    остановить:         sudo systemctl stop d-brain-bot"
        echo ""
        echo "  Установка целиком записана в: $LOG_FILE"
        echo ""
        return 0
    fi

    # Не притворяемся, что всё хорошо: показываем реальную причину.
    local status
    status=$(systemctl is-active d-brain-bot 2>/dev/null || echo "неизвестно")

    echo ""
    error "Бот не запустился (статус: $status)"
    echo ""

    local jlog
    jlog=$(journalctl -u d-brain-bot -n 50 --no-pager 2>/dev/null || echo "")

    if echo "$jlog" | grep -q "TelegramUnauthorizedError"; then
        warn "Telegram отклонил токен бота."
        echo "  Возьмите актуальный: @BotFather → /mybots → ваш бот → API Token"
        echo "  и впишите его в ${ENV_FILE}"
    elif echo "$jlog" | grep -q "ValidationError\|Field required"; then
        warn "В файле настроек не хватает обязательного ключа."
        echo "  Проверьте: ${ENV_FILE}"
    elif echo "$jlog" | grep -q "Not logged in"; then
        warn "Claude не авторизован."
        echo "  Выполните: claude setup-token"
        echo "  и впишите токен в ${ENV_FILE} строкой CLAUDE_CODE_OAUTH_TOKEN=<токен>"
    fi

    echo ""
    echo "  Последние записи журнала:"
    echo "  ------------------------------------------------------------"
    echo "$jlog" | tail -n 30
    echo "  ------------------------------------------------------------"
    echo ""
    echo "  После правки настроек перезапустите бота:"
    echo -e "    ${CYAN}sudo systemctl restart d-brain-bot${NC}"
    echo ""
    echo "  Полный лог установки: $LOG_FILE"
    echo ""
    # Выходим сразу и без общего обработчика ошибок: причина уже названа
    # выше конкретно, а поверх неё «установка прервалась на шаге...»
    # только сбило бы с толку.
    trap - ERR
    exit 1
}

# =============================================================================
# СЦЕНАРИИ
# =============================================================================

stage1_root() {
    print_banner

    echo "  Установщик сделает всё сам:"
    echo ""
    echo "    1. Подготовит сервер и обновит систему"
    echo "    2. Создаст отдельного пользователя для бота"
    echo "    3. Включит firewall и автообновления безопасности"
    echo "    4. Поставит Python, Node.js, uv и Claude CLI"
    echo "    5. Загрузит Гэл и спросит ключи доступа"
    echo "    6. Настроит автозапуск и расписание"
    echo ""
    echo "  Займёт 5–10 минут. Перезагрузка не потребуется."
    echo "  Держите под рукой ключи: Telegram, Deepgram, Todoist."
    echo ""

    ask "Начинаем? (Y/n):"
    read -r reply
    if [[ $reply =~ ^[Nn]$ ]]; then
        echo "Отменено."
        exit 0
    fi

    fix_dns
    check_os
    install_base_packages
    choose_user
    create_user
    grant_nopasswd_sudo
    copy_ssh_keys
    configure_firewall
    switch_to_user   # exec — сюда управление уже не вернётся
}

stage2_user() {
    # Имя юзера: из переменной (пришли из stage 1) или текущее.
    GAAL_USER="${GAAL_INSTALL_USER:-$(id -un)}"

    if [ -z "${GAAL_STAGE:-}" ]; then
        # Запустили сразу под обычным юзером — баннер ещё не показывали.
        print_banner
        echo "  Сервер уже подготовлен, продолжаю установку"
        echo "  под пользователем «${GAAL_USER}»."
        echo ""
        fix_dns
        check_os
        install_base_packages
    fi

    install_python
    install_nodejs
    install_claude_cli
    install_uv
    clone_repository
    create_env_file
    install_dependencies
    install_systemd_units
    authorize_claude
    final_check
}

# Под обычным юзером нужен рабочий sudo — иначе половина шагов не пройдёт.
require_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if ! have sudo; then
        error "Не найдена команда sudo"
        echo "  Запустите установщик от root — это нормальный способ:"
        echo -e "    ${CYAN}sudo -i${NC}, затем команда установки заново"
        exit 1
    fi

    if ! sudo -n true 2>/dev/null; then
        echo ""
        info "Понадобятся права администратора — введите пароль пользователя «$(id -un)»"
        if ! sudo -v; then
            error "Без прав администратора установка невозможна"
            echo "  Проще всего: зайдите на сервер под root и запустите установщик там."
            exit 1
        fi
    fi
}

main() {
    # Весь вывод дублируется в лог — чтобы было что прислать при проблемах.
    # stdin не трогаем: вопросы через read должны читаться с терминала.
    if [ -z "${GAAL_LOGGING:-}" ]; then
        export GAAL_LOGGING=1
        touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/gaal-install.log"
        chmod 644 "$LOG_FILE" 2>/dev/null || true
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    require_sudo

    # --stage2 / GAAL_STAGE=2 — внутренний режим: root уже отработал
    # и передал управление целевому пользователю.
    if [ "${1:-}" = "--stage2" ] || [ "${GAAL_STAGE:-}" = "2" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            error "Внутренняя ошибка: вторая часть установки не должна идти от root"
            exit 1
        fi
        stage2_user
        return
    fi

    if [ "$(id -u)" -eq 0 ]; then
        stage1_root
    else
        stage2_user
    fi
}

main "$@"
