#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =========================
# CONFIG
# =========================
TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~${TARGET_USER}")"

FIRA_CODE_NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip"
FONT_NAME="FiraCode Nerd Font"
FONT_SIZE=10

DEFAULT_PRESET="gruvbox-rainbow"
STARSHIP_PRESET="$DEFAULT_PRESET"
NON_INTERACTIVE=false
CUSTOM_PRESET=""
PACKAGES_INSTALLED=false

# =========================
# UTILS
# =========================
log() { printf '%s\n' "$*"; }

has_tty() { [[ -t 0 && -t 1 ]]; }

detect_terminal() {
  if [[ -n "${GNOME_TERMINAL_SCREEN-}" || -n "${GNOME_TERMINAL_SERVICE-}" ]]; then
    printf 'gnome-terminal'
    return
  fi
  if [[ -n "${KONSOLE_PROFILE_NAME-}" || -n "${KONSOLE_DBUS_SERVICE-}" ]]; then
    printf 'konsole'
    return
  fi
  if [[ -n "${ALACRITTY_SOCKET-}" ]]; then
    printf 'alacritty'
    return
  fi
  if [[ -n "${KITTY_PID-}" ]]; then
    printf 'kitty'
    return
  fi
  if [[ -n "${TERMINATOR_UUID-}" ]]; then
    printf 'terminator'
    return
  fi
  if [[ -n "${TMUX-}" ]]; then
    printf 'tmux'
    return
  fi
  if [[ -n "${STY-}" ]]; then
    printf 'screen'
    return
  fi

  local parent_proc
  parent_proc=$(ps -o comm= -p "$(ps -o ppid= -p $$)" 2>/dev/null | tr -d ' ')
  case "$parent_proc" in
    gnome-terminal*|gnome-terminal) printf 'gnome-terminal' ;; 
    gnome-console) printf 'gnome-console' ;; 
    alacritty) printf 'alacritty' ;; 
    konsole) printf 'konsole' ;; 
    xfce4-terminal) printf 'xfce4-terminal' ;; 
    xterm) printf 'xterm' ;; 
    kitty) printf 'kitty' ;; 
    terminator) printf 'terminator' ;; 
    urxvt) printf 'urxvt' ;; 
    wezterm) printf 'wezterm' ;; 
    *) printf '%s' "${parent_proc:-unknown}" ;; 
  esac
}

run_as_user() {
  sudo -u "$TARGET_USER" env HOME="$HOME_DIR" PATH="$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --preset)
        CUSTOM_PRESET="$2"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      *)
        log "Unknown arg: $1"
        exit 1
        ;;
    esac
  done
}

# =========================
# DISTRO
# =========================
get_distro() {
  . /etc/os-release
  echo "${ID:-}"
}

install_packages() {
  if $PACKAGES_INSTALLED; then
    return
  fi
  PACKAGES_INSTALLED=true

  case "$(get_distro)" in
    ubuntu|debian|linuxmint|pop|elementary)
      sudo apt-get update -y
      sudo apt-get install -y fish curl unzip fontconfig fzf git
      ;;
    fedora|rhel|centos)
      sudo dnf install -y fish curl unzip fontconfig fzf git
      ;;
    arch|manjaro)
      sudo pacman -Syu --noconfirm fish curl unzip fontconfig fzf git
      ;;
    opensuse|suse)
      sudo zypper refresh
      sudo zypper install -y fish curl unzip fontconfig fzf git
      ;;
    alpine)
      sudo apk update
      sudo apk add fish curl unzip fontconfig fzf git
      ;;
    *)
      log "Instalá manualmente dependencias: fish curl unzip fontconfig fzf git"
      exit 1
      ;;
  esac
}

# =========================
# INSTALLS
# =========================
install_fish() {
  command -v fish >/dev/null || install_packages
}

install_starship() {
  if ! command -v starship >/dev/null; then
    log "Instalando starship..."
    run_as_user bash -lc 'curl -fsSL https://starship.rs/install.sh | bash -s -- -y'
  else
    log "starship ya instalado"
  fi
}

install_fzf_if_needed() {
  if ! command -v fzf >/dev/null 2>&1; then
    log "Instalando fzf..."
    install_packages
  fi
}

# =========================
# PREVIEW ENV
# =========================
prepare_preview_env() {
  local PREVIEW_DIR="/tmp/starship-preview-env"
  mkdir -p "$PREVIEW_DIR"

  if [ ! -d "$PREVIEW_DIR/.git" ]; then
    git init "$PREVIEW_DIR" >/dev/null 2>&1
    touch "$PREVIEW_DIR/file.txt"
    (cd "$PREVIEW_DIR" && git add . && git commit -m "init" >/dev/null 2>&1 || true)
  fi
}

# =========================
# PRESET SELECTOR (fzf 🔥)
# =========================
choose_preset() {
  if [[ -n "$CUSTOM_PRESET" ]]; then
    if ! run_as_user starship preset -l | grep -qx "$CUSTOM_PRESET"; then
      log "Preset inválido: $CUSTOM_PRESET"
      exit 1
    fi
    STARSHIP_PRESET="$CUSTOM_PRESET"
    return
  fi

  if $NON_INTERACTIVE || ! has_tty; then
    log "No interactivo → usando preset default: $DEFAULT_PRESET"
    STARSHIP_PRESET="$DEFAULT_PRESET"
    return
  fi

  install_fzf_if_needed
  prepare_preview_env

  local tmp_out
  tmp_out="$(mktemp /tmp/fzf-choice-XXXXXX)"

  (
    cd /tmp/starship-preview-env

    export PATH="$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin"

    starship preset -l | fzf \
      --height=60% \
      --layout=reverse \
      --border \
      --prompt='🚀 Preset: ' \
      --preview "
        PREVIEW_FILE=/tmp/starship-preview.toml
        starship preset {} -o \$PREVIEW_FILE >/dev/null 2>&1

        export STARSHIP_CONFIG=\$PREVIEW_FILE
        export USER='$TARGET_USER'
        export HOSTNAME=devbox

        echo
        starship prompt
        echo
        echo '❯ git status'
        git status --short 2>/dev/null
        echo
      " \
      --preview-window=down:8:wrap \
      > "$tmp_out"
  )

  if [[ -s "$tmp_out" ]]; then
    STARSHIP_PRESET="$(cat "$tmp_out")"
  else
    STARSHIP_PRESET="$DEFAULT_PRESET"
  fi

  rm -f "$tmp_out"
}

# =========================
# STARSHIP CONFIG
# =========================
generate_starship_config() {
  mkdir -p "$HOME_DIR/.config"
  run_as_user starship preset "$STARSHIP_PRESET" -o "$HOME_DIR/.config/starship.toml"
  chown "$TARGET_USER":"$TARGET_USER" "$HOME_DIR/.config/starship.toml"
}

# =========================
# FISH CONFIG
# =========================
configure_fish() {
  local config="$HOME_DIR/.config/fish/config.fish"
  mkdir -p "$(dirname "$config")"

  if ! grep -q "starship init fish" "$config" 2>/dev/null; then
    cat >> "$config" <<'EOF'

# Starship
set -gx PATH $HOME/.local/bin $PATH
if type -q starship
    starship init fish | source
end
EOF
  fi

  chown -R "$TARGET_USER":"$TARGET_USER" "$HOME_DIR/.config/fish"
}

# =========================
# FONT
# =========================
install_font() {
  local dir="$HOME_DIR/.local/share/fonts"
  mkdir -p "$dir"

  local tmp
  tmp="$(mktemp /tmp/font-XXXXXX.zip)"

  log "Instalando FiraCode Nerd Font..."
  curl -fsSL "$FIRA_CODE_NERD_FONT_URL" -o "$tmp"
  unzip -o "$tmp" -d "$dir"
  rm -f "$tmp"

  fc-cache -f "$dir" || true
  chown -R "$TARGET_USER":"$TARGET_USER" "$dir"
}

# =========================
# TERMINAL FONT
# =========================
configure_terminal_font() {
  local chosen="${FONT_NAME} ${FONT_SIZE}"

  if command -v gsettings >/dev/null 2>&1; then
    if gsettings writable org.gnome.Ptyxis font-name >/dev/null 2>&1; then
      log "Configurando GNOME Console (Ptyxis)..."
      gsettings set org.gnome.Ptyxis font-name "$chosen"
      gsettings set org.gnome.Ptyxis use-system-font false
      return
    fi

    if gsettings writable org.gnome.Terminal.Legacy.Profile:/ >/dev/null 2>&1; then
      log "Configurando GNOME Terminal..."
      local profile
      profile=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
      gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/" font "'$chosen'"
      gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/" use-system-font false
      return
    fi
  fi

  if command -v kwriteconfig5 >/dev/null 2>&1 && [ -f "$HOME_DIR/.config/konsolerc" ]; then
    log "Configurando Konsole..."
    local profile_name
    profile_name=$(grep '^DefaultProfile=' "$HOME_DIR/.config/konsolerc" | cut -d'=' -f2)
    local profile_file="$HOME_DIR/.local/share/konsole/$profile_name"
    if [ -f "$profile_file" ]; then
      if grep -q '^Font=' "$profile_file"; then
        sed -i "s|^Font=.*|Font=${FONT_NAME},${FONT_SIZE},-1,5,50,0,0,0,0,0|" "$profile_file"
      else
        echo "Font=${FONT_NAME},${FONT_SIZE},-1,5,50,0,0,0,0,0,0" >> "$profile_file"
      fi
      chown "$TARGET_USER":"$TARGET_USER" "$profile_file"
      return
    fi
  fi

  log "Config manual requerida: $chosen"
}

# =========================
# MAIN
# =========================
main() {
  parse_args "$@"
  log "Usuario: $TARGET_USER"
  log "Distro detectada: $(get_distro)"
  log "Terminal detectado: $(detect_terminal) (TERM=$TERM)"

  install_fish
  install_starship
  choose_preset
  generate_starship_config
  configure_fish
  install_font
  configure_terminal_font

  log "✔ Listo. Reiniciá la terminal o ejecutá: fish"
}

main "$@"