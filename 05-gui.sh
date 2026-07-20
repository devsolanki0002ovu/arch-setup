#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 05-gui.sh — Desktop Environment & Theming Configuration
# ─────────────────────────────────────────────────────────────────────────────
# Configures LXQt + Openbox desktop, GTK/Qt theme synchronization, Firefox
# enterprise policies, desktop entry renames, MIME associations, and all
# visual settings.
#
# All configs are written to /etc/skel so the user inherits them.
# Uses xmlstarlet for XML edits. Uses safe_write for atomic operations.
#
# Depends on: globals.env, 00-lib.sh, 04-core.sh (user + services)
# ─────────────────────────────────────────────────────────────────────────────

set_stage "05-gui"

_ROOT="${GTLTSC_MOUNT_ROOT}"
_SKEL="${_ROOT}/etc/skel"
_USER_HOME="${_ROOT}/home/${GTLTSC_USERNAME}"

verify_mount "${_ROOT}" "Root filesystem"

# ═══════════════════════════════════════════════════════════════════════════════
#  SDDM — DISPLAY MANAGER (NO AUTOLOGIN)
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring SDDM (no autologin)..."

ensure_dir "${_ROOT}/etc/sddm.conf.d"

safe_write_heredoc "${_ROOT}/etc/sddm.conf.d/10-ltsc.conf" <<'EOF'
[Theme]
Current=breeze

[General]
# No autologin — password required at every boot

[Users]
# Default settings — no special user filtering
EOF

log "SDDM configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  LXQT THEME — LEECH WITH FALLBACK
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring LXQt theme..."

# Determine available theme
_lxqt_theme="${GTLTSC_LXQT_THEME}"
if [[ ! -d "${_ROOT}/usr/share/lxqt/themes/${_lxqt_theme}" ]]; then
    warn "LXQt theme '${_lxqt_theme}' not found, trying fallback: ${GTLTSC_LXQT_THEME_FALLBACK}"
    _lxqt_theme="${GTLTSC_LXQT_THEME_FALLBACK}"
    if [[ ! -d "${_ROOT}/usr/share/lxqt/themes/${_lxqt_theme}" ]]; then
        warn "Fallback theme also not found, using first available theme"
        _lxqt_theme=$(ls -1 "${_ROOT}/usr/share/lxqt/themes/" 2>/dev/null | head -1 || echo "frost")
    fi
fi
log "Using LXQt theme: ${_lxqt_theme}"

# ── LXQt Session Configuration ──────────────────────────────────────────────
ensure_dir "${_SKEL}/.config/lxqt"

safe_write_heredoc "${_SKEL}/.config/lxqt/session.conf" <<EOF
[General]
__userfile__=true

[Mouse]
cursor_size=${GTLTSC_CURSOR_SIZE}
cursor_theme=${GTLTSC_CURSOR_THEME}

[Environment]
QT_QPA_PLATFORMTHEME=qt6ct
EOF

# ── LXQt General Settings ───────────────────────────────────────────────────
safe_write_heredoc "${_SKEL}/.config/lxqt/lxqt.conf" <<EOF
[General]
__userfile__=true
theme=${_lxqt_theme}
icon_theme=${GTLTSC_ICON_THEME}
single_click_activate=false

[Qt]
font="${GTLTSC_FONT}"
font_point_size=${GTLTSC_FONT_SIZE}
style=Fusion
EOF

# ── LXQt Panel Configuration ────────────────────────────────────────────────
safe_write_heredoc "${_SKEL}/.config/lxqt/panel.conf" <<EOF
[General]
__userfile__=true

[panel1]
alignment=Left
animation-duration=0
auto-hide=false
desktop=0
hidable=false
iconSize=24
lineCount=1
lockPanel=true
panelSize=32
position=Bottom
reserve-space=true
show-delay=0
width=100
width-percent=true

[panel1/plugins]
1=mainmenu
2=desktopswitch
3=quicklaunch
4=taskbar
5=tray
6=statusnotifier
7=volume
8=clock

[panel1/plugins/clock]
type=clock
showDate=true
dateFormat=short

[panel1/plugins/mainmenu]
type=mainmenu

[panel1/plugins/taskbar]
type=taskbar
showDesktopNum=0

[panel1/plugins/tray]
type=tray

[panel1/plugins/volume]
type=volume

[panel1/plugins/quicklaunch]
type=quicklaunch

[panel1/plugins/desktopswitch]
type=desktopswitch
rows=1

[panel1/plugins/statusnotifier]
type=statusnotifier
EOF

# ═══════════════════════════════════════════════════════════════════════════════
#  OPENBOX WINDOW MANAGER
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring Openbox..."

ensure_dir "${_SKEL}/.config/openbox"

# ── Openbox rc.xml — Windows-like keybinds, no compositor ────────────────────
safe_write_heredoc "${_SKEL}/.config/openbox/rc.xml" <<'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"
                xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow"><name>Noto Sans</name><size>10</size><weight>Bold</weight><slant>Normal</slant></font>
    <font place="InactiveWindow"><name>Noto Sans</name><size>10</size><weight>Bold</weight><slant>Normal</slant></font>
    <font place="MenuHeader"><name>Noto Sans</name><size>10</size><weight>Bold</weight><slant>Normal</slant></font>
    <font place="MenuItem"><name>Noto Sans</name><size>10</size><weight>Normal</weight><slant>Normal</slant></font>
    <font place="ActiveOnScreenDisplay"><name>Noto Sans</name><size>10</size><weight>Bold</weight><slant>Normal</slant></font>
    <font place="InactiveOnScreenDisplay"><name>Noto Sans</name><size>10</size><weight>Bold</weight><slant>Normal</slant></font>
  </theme>
  <desktops>
    <number>2</number>
    <firstdesk>1</firstdesk>
    <names><name>Desktop 1</name><name>Desktop 2</name></names>
    <popupTime>500</popupTime>
  </desktops>
  <resize><drawContents>yes</drawContents><popupShow>Nonpixel</popupShow><popupPosition>Center</popupPosition><popupFixedPosition><x>10</x><y>10</y></popupFixedPosition></resize>
  <keyboard>
    <!-- Windows-like keybinds -->
    <keybind key="A-F4"><action name="Close"/></keybind>
    <keybind key="A-F9"><action name="Iconify"/></keybind>
    <keybind key="A-F10"><action name="ToggleMaximize"/></keybind>
    <keybind key="A-Tab"><action name="NextWindow"><finalactions><action name="Focus"/><action name="Raise"/><action name="Unshade"/></finalactions></action></keybind>
    <keybind key="A-S-Tab"><action name="PreviousWindow"><finalactions><action name="Focus"/><action name="Raise"/><action name="Unshade"/></finalactions></action></keybind>
    <keybind key="W-d"><action name="ToggleShowDesktop"/></keybind>
    <keybind key="W-e"><action name="Execute"><command>pcmanfm-qt</command></action></keybind>
    <keybind key="W-l"><action name="Execute"><command>lxqt-leave --lockscreen</command></action></keybind>
    <keybind key="W-r"><action name="Execute"><command>lxqt-runner</command></action></keybind>
    <keybind key="C-A-Delete"><action name="Execute"><command>lxqt-leave</command></action></keybind>
    <keybind key="W-Left"><action name="UnmaximizeFull"/><action name="MoveResizeTo"><x>0</x><y>0</y><width>50%</width><height>100%</height></action></keybind>
    <keybind key="W-Right"><action name="UnmaximizeFull"/><action name="MoveResizeTo"><x>50%</x><y>0</y><width>50%</width><height>100%</height></action></keybind>
    <keybind key="W-Up"><action name="Maximize"/></keybind>
    <keybind key="W-Down"><action name="Unmaximize"/></keybind>
    <keybind key="Print"><action name="Execute"><command>lximage-qt --screenshot</command></action></keybind>
  </keyboard>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>
    <screenEdgeWarpMouse>false</screenEdgeWarpMouse>
    <context name="Frame"><mousebind button="A-Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind><mousebind button="A-Left" action="Drag"><action name="Move"/></mousebind><mousebind button="A-Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind><mousebind button="A-Right" action="Drag"><action name="Resize"/></mousebind></context>
    <context name="Titlebar"><mousebind button="Left" action="Drag"><action name="Move"/></mousebind><mousebind button="Left" action="DoubleClick"><action name="ToggleMaximize"/></mousebind></context>
    <context name="Client"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind><mousebind button="Middle" action="Press"><action name="Focus"/><action name="Raise"/></mousebind><mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind></context>
    <context name="Desktop"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind></context>
    <context name="Root"><mousebind button="Right" action="Press"><action name="ShowMenu"><menu>root-menu</menu></action></mousebind></context>
  </mouse>
  <applications>
    <application class="*">
      <decor>yes</decor>
    </application>
  </applications>
</openbox_config>
XMLEOF

# ── Openbox autostart ────────────────────────────────────────────────────────
safe_write_heredoc "${_SKEL}/.config/openbox/autostart" <<'EOF'
# God-Tier LTSC — Openbox Autostart
# No compositor — GeForce 210 Nouveau is too limited
EOF

# ── Openbox environment ──────────────────────────────────────────────────────
safe_write_heredoc "${_SKEL}/.config/openbox/environment" <<'EOF'
# God-Tier LTSC — Openbox Environment
export QT_QPA_PLATFORMTHEME=qt6ct
EOF

log "Openbox configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  GTK THEMING — GTK2, GTK3, GTK4
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring GTK themes..."

# ── GTK2 ─────────────────────────────────────────────────────────────────────
safe_write_heredoc "${_SKEL}/.gtkrc-2.0" <<EOF
# God-Tier LTSC — GTK2 Configuration
gtk-theme-name="${GTLTSC_GTK_THEME}"
gtk-icon-theme-name="${GTLTSC_ICON_THEME}"
gtk-cursor-theme-name="${GTLTSC_CURSOR_THEME}"
gtk-cursor-theme-size=${GTLTSC_CURSOR_SIZE}
gtk-font-name="${GTLTSC_FONT} ${GTLTSC_FONT_SIZE}"
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
EOF

# ── GTK3 ─────────────────────────────────────────────────────────────────────
ensure_dir "${_SKEL}/.config/gtk-3.0"

safe_write_heredoc "${_SKEL}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=${GTLTSC_GTK_THEME}
gtk-icon-theme-name=${GTLTSC_ICON_THEME}
gtk-cursor-theme-name=${GTLTSC_CURSOR_THEME}
gtk-cursor-theme-size=${GTLTSC_CURSOR_SIZE}
gtk-font-name=${GTLTSC_FONT} ${GTLTSC_FONT_SIZE}
gtk-application-prefer-dark-theme=true
gtk-decoration-layout=menu:minimize,maximize,close
EOF

# ── GTK4 ─────────────────────────────────────────────────────────────────────
ensure_dir "${_SKEL}/.config/gtk-4.0"

safe_write_heredoc "${_SKEL}/.config/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=${GTLTSC_GTK_THEME}
gtk-icon-theme-name=${GTLTSC_ICON_THEME}
gtk-cursor-theme-name=${GTLTSC_CURSOR_THEME}
gtk-cursor-theme-size=${GTLTSC_CURSOR_SIZE}
gtk-font-name=${GTLTSC_FONT} ${GTLTSC_FONT_SIZE}
gtk-application-prefer-dark-theme=true
EOF

log "GTK theming configured (GTK2/3/4) ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  QT THEMING — QT5/QT6 VIA QT6CT
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring Qt theming via qt6ct..."

ensure_dir "${_SKEL}/.config/qt6ct"

safe_write_heredoc "${_SKEL}/.config/qt6ct/qt6ct.conf" <<EOF
[Appearance]
color_scheme_path=
custom_palette=false
icon_theme=${GTLTSC_ICON_THEME}
standard_dialogs=default
style=Fusion

[Fonts]
fixed="${GTLTSC_FONT},${GTLTSC_FONT_SIZE},-1,5,50,0,0,0,0,0"
general="${GTLTSC_FONT},${GTLTSC_FONT_SIZE},-1,5,50,0,0,0,0,0"

[Interface]
activate_item_on_single_click=0
buttonbox_layout=0
cursor_flash_time=1000
dialog_buttons_have_icons=1
double_click_interval=400
gui_effects=@Invalid()
keyboard_scheme=0
menus_have_icons=true
show_shortcuts_in_context_menus=true
stylesheets=@Invalid()
toolbutton_style=4
underline_shortcut=1
wheel_scroll_lines=3
EOF

# ── Environment variable for Qt platform theme ──────────────────────────────
ensure_dir "${_ROOT}/etc/environment.d"
safe_write "${_ROOT}/etc/environment.d/90-ui.conf" "QT_QPA_PLATFORMTHEME=qt6ct"

log "Qt theming configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  DESKTOP BACKGROUND — SOLID #111111
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring desktop background..."

ensure_dir "${_SKEL}/.config/pcmanfm-qt/lxqt"

safe_write_heredoc "${_SKEL}/.config/pcmanfm-qt/lxqt/settings.conf" <<EOF
[Desktop]
BgColor=${GTLTSC_DESKTOP_BG_COLOR}
DesktopIconSize=48
Font="${GTLTSC_FONT},${GTLTSC_FONT_SIZE}"
ShowHidden=false
Wallpaper=
WallpaperMode=color
DesktopCellMargins=@Size(3 1)
EOF

log "Desktop background set to ${GTLTSC_DESKTOP_BG_COLOR} ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  CURSOR THEME (SYSTEM-WIDE)
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring system cursor theme..."

ensure_dir "${_ROOT}/usr/share/icons/default"

safe_write_heredoc "${_ROOT}/usr/share/icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=${GTLTSC_CURSOR_THEME}
EOF

log "Cursor theme set to ${GTLTSC_CURSOR_THEME} ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  FIREFOX ENTERPRISE POLICIES
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring Firefox enterprise policies..."

ensure_dir "${_ROOT}/etc/firefox/policies"

# Build policy JSON — use printf to avoid any injection issues
_firefox_policy=$(cat <<'POLICY_HEREDOC'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableFirefoxAccounts": true,
    "DisableSetDesktopBackground": true,
    "DontCheckDefaultBrowser": true,
    "NoDefaultBookmarks": true,
    "OfferToSaveLogins": false,
    "PasswordManagerEnabled": false,
    "Homepage": {
      "URL": "about:blank",
      "Locked": false,
      "StartPage": "homepage"
    },
    "FirefoxHome": {
      "Search": true,
      "TopSites": false,
      "SponsoredTopSites": false,
      "Highlights": false,
      "Pocket": false,
      "SponsoredPocket": false,
      "Snippets": false,
      "Locked": false
    },
    "UserMessaging": {
      "WhatsNew": false,
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "UrlbarInterventions": false,
      "SkipOnboarding": true,
      "MoreFromMozilla": false
    },
    "EnableTrackingProtection": {
      "Value": true,
      "Locked": false,
      "Cryptomining": true,
      "Fingerprinting": true
    },
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": ""
  }
}
POLICY_HEREDOC
)

safe_write "${_ROOT}/etc/firefox/policies/policies.json" "${_firefox_policy}"

# Validate JSON syntax
if safe_chroot "python3 -m json.tool /etc/firefox/policies/policies.json" &>/dev/null; then
    log "Firefox policy JSON validated ✓"
else
    warn "Firefox policy JSON validation failed — policies may not load"
fi

log "Firefox enterprise policies configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  DESKTOP ENTRY RENAMES
# ═══════════════════════════════════════════════════════════════════════════════

log "Renaming desktop entries..."

for entry in "${GTLTSC_DESKTOP_RENAMES[@]}"; do
    _desktop_file="${entry%%:*}"
    _new_name="${entry#*:}"
    _desktop_path="${_ROOT}/usr/share/applications/${_desktop_file}"

    if [[ ! -f "${_desktop_path}" ]]; then
        warn "Desktop entry not found, skipping: ${_desktop_file}"
        continue
    fi

    # Only replace the unlocalized Name= line (not Name[xx]= lines)
    # This preserves all localization and comments
    if grep -q "^Name=" "${_desktop_path}"; then
        # Check if already renamed (idempotent)
        _current_name=$(grep "^Name=" "${_desktop_path}" | head -1 | cut -d= -f2-)
        if [[ "${_current_name}" == "${_new_name}" ]]; then
            log "Desktop entry already renamed: ${_desktop_file} → ${_new_name}"
            continue
        fi
        sed -i "s|^Name=.*|Name=${_new_name}|" "${_desktop_path}" \
            || warn "Failed to rename: ${_desktop_file}"
        log "Renamed: ${_desktop_file} → ${_new_name}"
    else
        warn "No Name= key found in ${_desktop_file}"
    fi
done

log "Desktop entries renamed ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  MIME ASSOCIATIONS
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring MIME associations..."

ensure_dir "${_SKEL}/.config"

safe_write_heredoc "${_SKEL}/.config/mimeapps.list" <<'EOF'
[Default Applications]
text/html=firefox.desktop
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
x-scheme-handler/about=firefox.desktop
x-scheme-handler/unknown=firefox.desktop
inode/directory=pcmanfm-qt.desktop
application/pdf=qpdfview.desktop
image/jpeg=lximage-qt.desktop
image/png=lximage-qt.desktop
image/gif=lximage-qt.desktop
image/bmp=lximage-qt.desktop
image/svg+xml=lximage-qt.desktop
text/plain=featherpad.desktop
application/x-shellscript=featherpad.desktop
EOF

log "MIME associations configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  XDG USER DIRECTORIES
# ═══════════════════════════════════════════════════════════════════════════════

log "Configuring XDG user directories..."

ensure_dir "${_SKEL}/.config"

safe_write_heredoc "${_SKEL}/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
EOF

log "XDG directories configured ✓"

# ═══════════════════════════════════════════════════════════════════════════════
#  COPY SKEL TO EXISTING USER
# ═══════════════════════════════════════════════════════════════════════════════

log "Copying skel configuration to user: ${GTLTSC_USERNAME}"

if [[ -d "${_USER_HOME}" ]]; then
    # Copy all skel files, preserving directory structure
    cp -rT "${_SKEL}" "${_USER_HOME}"
    # Fix ownership
    safe_chroot "chown -R ${GTLTSC_USERNAME}:${GTLTSC_USERNAME} /home/${GTLTSC_USERNAME}"
    log "User configuration applied ✓"
else
    warn "User home directory not found: ${_USER_HOME}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
#  XDG DIRECTORIES — CREATE FOR USER
# ═══════════════════════════════════════════════════════════════════════════════

log "Creating XDG directories for user..."
_xdg_dirs=(Desktop Downloads Documents Music Pictures Videos Templates Public)
for dir in "${_xdg_dirs[@]}"; do
    ensure_dir "${_USER_HOME}/${dir}"
done
safe_chroot "chown -R ${GTLTSC_USERNAME}:${GTLTSC_USERNAME} /home/${GTLTSC_USERNAME}"

log "GUI configuration stage complete ✓"
