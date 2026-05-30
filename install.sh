#!/usr/bin/env bash
# VoiceInk auto-installer for macOS
# Собирает open-source VoiceInk из исходников. Без триала, навсегда бесплатно.
#
# Источник: https://github.com/Beingpax/VoiceInk
#   ⭐ ~4,800 звёзд · 🍴 650+ форков · 📜 GPL v3 · с октября 2024
#
# Скрипт ТОЛЬКО автоматизирует сборку. В код VoiceInk не вносит изменений.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

say() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}!!${NC} $1"; }
fail() { echo -e "${RED}!!${NC} $1"; exit 1; }

# --- 1. Проверки окружения --------------------------------------------------
say "Проверяю систему..."

if [[ "$(uname)" != "Darwin" ]]; then
  fail "Скрипт работает только на macOS."
fi

MACOS_VER=$(sw_vers -productVersion | cut -d. -f1)
if (( MACOS_VER < 14 )); then
  fail "Нужен macOS 14.4 или новее. У тебя: $(sw_vers -productVersion)"
fi

FREE_GB=$(df -g / | tail -1 | awk '{print $4}')
if (( FREE_GB < 30 )); then
  warn "Свободно только ${FREE_GB} ГБ. Нужно минимум 30 ГБ для Xcode + сборки."
  read -p "Продолжать? (y/n) " -n 1 -r; echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# --- 2. Homebrew + cmake ----------------------------------------------------
if ! command -v brew &>/dev/null; then
  say "Ставлю Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if ! command -v cmake &>/dev/null; then
  say "Ставлю cmake..."
  brew install cmake
else
  say "cmake уже стоит."
fi

# --- 3. Проверка Xcode ------------------------------------------------------
if [[ ! -d /Applications/Xcode.app ]]; then
  fail "Нужен полный Xcode из App Store (~10 ГБ).
Открой App Store, поиск 'Xcode', нажми Get → Install.
После установки запусти этот скрипт снова."
fi

CURRENT_DEV=$(xcode-select -p)
if [[ "$CURRENT_DEV" != "/Applications/Xcode.app/Contents/Developer" ]]; then
  say "Переключаю xcode-select на полный Xcode (нужен пароль)..."
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
fi

# --- 4. Клонирование репо VoiceInk ------------------------------------------
TOOLS_DIR="$HOME/Tools"
mkdir -p "$TOOLS_DIR"

if [[ -d "$TOOLS_DIR/VoiceInk" ]]; then
  say "Репо VoiceInk уже есть, обновляю..."
  cd "$TOOLS_DIR/VoiceInk" && git pull
else
  say "Клонирую VoiceInk из исходников..."
  cd "$TOOLS_DIR"
  git clone https://github.com/Beingpax/VoiceInk.git
  cd VoiceInk
fi

# --- 5. Сборка --------------------------------------------------------------
say "Собираю VoiceInk (5–15 минут на M-серии Mac)..."
make local

# --- 6. Установка в /Applications -------------------------------------------
if [[ -d /Applications/VoiceInk.app ]]; then
  warn "В /Applications/ уже есть VoiceInk. Удаляю старую версию..."
  rm -rf /Applications/VoiceInk.app
fi

mv ~/Downloads/VoiceInk.app /Applications/VoiceInk.app
xattr -cr /Applications/VoiceInk.app
say "VoiceInk установлен в /Applications/"

# --- 7. Выбор и скачивание модели Whisper -----------------------------------
MODELS_DIR="$HOME/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels"
mkdir -p "$MODELS_DIR"

# Определяем железо — рекомендация по умолчанию зависит от RAM
RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
if (( RAM_GB <= 8 )); then
  DEFAULT_CHOICE=2  # Turbo Quantized
else
  DEFAULT_CHOICE=3  # Turbo full
fi

cat <<EOF

  Выбери модель Whisper:
    1) Apple Speech         — 0 МБ, нативно в macOS 26+ (русский — отдельно)
    2) Large v3 Turbo Quant — 547 МБ, ★★★★★, для 8 ГБ RAM ← дефолт на твоём железе
    3) Large v3 Turbo full  — 1.5 ГБ, ★★★★★, для 16+ ГБ RAM
    4) Large v3 full        — 2.9 ГБ, ★★★★★, для M3/M4 Pro

  У тебя ${RAM_GB} ГБ RAM. Рекомендация: вариант ${DEFAULT_CHOICE}.

EOF
read -p "  Какой ставим? [1/2/3/4, Enter = $DEFAULT_CHOICE]: " CHOICE
CHOICE=${CHOICE:-$DEFAULT_CHOICE}

case $CHOICE in
  1)
    say "Apple Speech — нативная, скачивать ничего не надо."
    say "После запуска: AI Models → Local → Apple Speech → Set as Default"
    say "Для русского: System Settings → Keyboard → Dictation → добавь Russian"
    MODEL_FILE=""
    ;;
  2) MODEL_FILE="ggml-large-v3-turbo-q5_0.bin" ;;
  3) MODEL_FILE="ggml-large-v3-turbo.bin" ;;
  4) MODEL_FILE="ggml-large-v3.bin" ;;
  *) fail "Неверный выбор: $CHOICE" ;;
esac

if [[ -n "$MODEL_FILE" ]]; then
  if [[ ! -f "$MODELS_DIR/$MODEL_FILE" ]]; then
    say "Скачиваю модель $MODEL_FILE..."
    curl -L --progress-bar \
      -o "$MODELS_DIR/$MODEL_FILE" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"
  else
    say "Модель $MODEL_FILE уже скачана."
  fi
fi

# --- 8. Запуск --------------------------------------------------------------
say "Запускаю VoiceInk..."
open /Applications/VoiceInk.app

cat <<'EOF'

  ╔════════════════════════════════════════════════════════════╗
  ║  ГОТОВО! Что делать дальше:                                ║
  ╠════════════════════════════════════════════════════════════╣
  ║                                                            ║
  ║  1. В VoiceInk → AI Models → Local                         ║
  ║     Выбери "Large v3 Turbo (Quantized)" → Set as Default   ║
  ║     (или "Apple Speech" если macOS 26+ и нужно ещё легче)  ║
  ║                                                            ║
  ║  2. Transcription Language → Russian                       ║
  ║     (для Apple Speech нужно скачать русский в              ║
  ║      System Settings → Keyboard → Dictation)               ║
  ║                                                            ║
  ║  3. Дай разрешения:                                        ║
  ║     - Microphone                                           ║
  ║     - Accessibility (вставка текста)                       ║
  ║     - Input Monitoring (глобальный хоткей)                 ║
  ║                                                            ║
  ║  4. Settings → выбери Hotkey (Right Cmd / fn / F5)         ║
  ║                                                            ║
  ║  5. Тестируй: курсор в Telegram → зажал хоткей →           ║
  ║     сказал → отпустил → текст вставился                    ║
  ║                                                            ║
  ╚════════════════════════════════════════════════════════════╝

Спасибо автору VoiceInk: https://github.com/Beingpax/VoiceInk
Если хочешь поддержать — купи официальную лицензию на voiceink.com
EOF
