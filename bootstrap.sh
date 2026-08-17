#!/bin/bash

# =============================================================================
# Гэл — шаг 1: подготовка сервера
# =============================================================================
# Запускается от root на свежей VPS. Создаёт обычного пользователя,
# настраивает firewall и базовую защиту, затем перезагружает машину.
#
# Работать под root опасно: любая ошибка в программе или взлом дают
# злоумышленнику весь сервер целиком. Поэтому бот будет жить
# под обычным пользователем, которого мы сейчас и создадим.
#
# Запуск:
#   bash <(curl -fsSL https://raw.githubusercontent.com/AlekdandrDG/Gaal_Secretar/main/bootstrap.sh)
#
# После перезагрузки подключитесь заново под новым пользователем
# и запустите шаг 2 — setup.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

SETUP_URL="https://raw.githubusercontent.com/AlekdandrDG/Gaal_Secretar/main/setup.sh"

info()    { echo -e "${CYAN}[*]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[X]${NC} $1"; }

echo ""
echo -e "${PURPLE}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║                                                           ║"
echo "  ║           ГЭЛ — ШАГ 1: ПОДГОТОВКА СЕРВЕРА                 ║"
echo "  ║                                                           ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Если скрипт запустили НЕ от root, значит пользователь уже есть
# и подготовка сервера, скорее всего, пройдена. Предлагаем перейти к шагу 2.
# -----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    warn "Этот шаг выполняется от root, а вы вошли как «$(whoami)»."
    echo ""
    echo "  Если сервер уже подготовлен (пользователь создан) —"
    echo "  переходите сразу к шагу 2, установке Гэл:"
    echo ""
    echo -e "    ${CYAN}bash <(curl -fsSL $SETUP_URL)${NC}"
    echo ""
    read -p "Запустить шаг 2 прямо сейчас? (Y/n): " -r REPLY
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        exit 0
    fi

    TEMP_SCRIPT=$(mktemp /tmp/setup-XXXXXX.sh)
    if command -v curl &> /dev/null; then
        curl -fsSL "$SETUP_URL" -o "$TEMP_SCRIPT"
    elif command -v wget &> /dev/null; then
        wget -q "$SETUP_URL" -O "$TEMP_SCRIPT"
    else
        error "Не найдены ни curl, ни wget. Установите: sudo apt install curl"
        exit 1
    fi
    [ -s "$TEMP_SCRIPT" ] || { error "Не удалось скачать setup.sh"; rm -f "$TEMP_SCRIPT"; exit 1; }
    chmod +x "$TEMP_SCRIPT"
    # exec, а не пайп: иначе скрипт не сможет задавать вопросы
    exec bash "$TEMP_SCRIPT"
fi

echo "  Сейчас мы подготовим сервер к работе:"
echo ""
echo "    1. Обновим систему"
echo "    2. Создадим обычного пользователя (работать под root опасно)"
echo "    3. Настроим firewall — пропускать только SSH"
echo "    4. Включим автоматические обновления безопасности"
echo "    5. Перезагрузим сервер"
echo ""
echo "  Займёт 3–5 минут. Вам понадобится придумать имя пользователя и пароль."
echo ""
read -p "$(echo -e "${YELLOW}?${NC} Начинаем? (Y/n): ")" -r REPLY
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Отменено."
    exit 0
fi

# -----------------------------------------------------------------------------
# 1. Обновление системы
# -----------------------------------------------------------------------------
echo ""
info "Обновляю список пакетов..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
info "Устанавливаю базовые пакеты..."
apt-get install -y -qq curl wget sudo ufw >/dev/null 2>&1
success "Система обновлена"

# -----------------------------------------------------------------------------
# 2. Создание пользователя
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}${BOLD}--> Создание пользователя${NC}"
echo ""
echo "  Под этим пользователем будет работать Гэл."
echo "  Имя — латиницей, без пробелов. Например: gaal"
echo ""

while true; do
    read -p "$(echo -e "${YELLOW}?${NC} Имя пользователя [Enter = gaal]: ")" -r NEW_USER
    NEW_USER=${NEW_USER:-gaal}

    if [[ ! "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error "Только строчные латинские буквы, цифры, дефис и подчёркивание"
        continue
    fi
    if id "$NEW_USER" &>/dev/null; then
        warn "Пользователь «$NEW_USER» уже существует"
        read -p "Использовать его? (Y/n): " -r REPLY
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            USER_EXISTED=1
            break
        fi
        continue
    fi
    break
done

if [ -z "${USER_EXISTED:-}" ]; then
    echo ""
    echo "  Придумайте пароль для «$NEW_USER»."
    echo "  Не используйте тот же, что у root."
    echo -e "  ${YELLOW}При вводе пароль не отображается — это нормально.${NC}"
    echo ""

    adduser --gecos "" "$NEW_USER"
    success "Пользователь «$NEW_USER» создан"
fi

usermod -aG sudo "$NEW_USER"
success "Права администратора выданы"

# Переносим SSH-ключи root'а, если вход настроен по ключу
if [ -f /root/.ssh/authorized_keys ]; then
    USER_HOME=$(getent passwd "$NEW_USER" | cut -d: -f6)
    mkdir -p "$USER_HOME/.ssh"
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    success "SSH-ключи скопированы новому пользователю"
fi

# -----------------------------------------------------------------------------
# 3. Firewall
# -----------------------------------------------------------------------------
echo ""
echo -e "${CYAN}${BOLD}--> Настройка firewall${NC}"
echo ""

ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null
ufw --force enable >/dev/null
success "Firewall включён — снаружи открыт только SSH"

# -----------------------------------------------------------------------------
# 4. Автообновления безопасности
# -----------------------------------------------------------------------------
echo ""
info "Включаю автоматические обновления безопасности..."
apt-get install -y -qq unattended-upgrades >/dev/null 2>&1 || true
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
success "Автообновления включены"

# -----------------------------------------------------------------------------
# 5. Перезагрузка
# -----------------------------------------------------------------------------
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║              СЕРВЕР ГОТОВ. ЧТО ДАЛЬШЕ                     ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Сейчас сервер перезагрузится, и связь оборвётся — это нормально."
echo ""
echo "  Через 1–2 минуты подключитесь заново, но уже под новым"
echo "  пользователем (не под root):"
echo ""
echo -e "    ${CYAN}${BOLD}ssh $NEW_USER@${SERVER_IP:-ВАШ_IP}${NC}"
echo ""
echo "  Пароль — тот, что вы только что придумали для «$NEW_USER»."
echo ""
echo "  Затем запустите шаг 2 — установку Гэл:"
echo ""
echo -e "    ${CYAN}${BOLD}bash <(curl -fsSL $SETUP_URL)${NC}"
echo ""
echo -e "  ${YELLOW}Запишите эти две команды — они понадобятся после перезагрузки.${NC}"
echo ""

read -p "$(echo -e "${YELLOW}?${NC} Перезагрузить сервер сейчас? (Y/n): ")" -r REPLY
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    warn "Перезагрузка отложена. Выполните её вручную: reboot"
    exit 0
fi

echo ""
info "Перезагружаю..."
sleep 2
reboot
