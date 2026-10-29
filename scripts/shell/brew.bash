# shellcheck shell=bash
# Linux Formulas front end for Homebrew; source it from your shell profile.
# It makes `brew` the one command for every package manager on the machine:
#
#   brew install NAME     `brew app install`: tap catalog (with aliases), then an
#                         exact Homebrew formula/Linux cask, then exact matches
#                         on Flathub, pacman, the AUR and GitHub releases.
#   brew upgrade          Homebrew, the whole system (one pacman/AUR or dnf
#                         transaction), Flatpak apps and runtimes, release apps.
#   brew upgrade NAME     Upgrade NAME through whichever manager owns it.
#   brew uninstall NAME   Remove NAME through whichever manager owns it.
#   brew list | outdated  Packages / pending updates from every manager.
#   brew info | search X  Details or matches from every manager.
#
# Packages installed with pacman, an AUR helper, Shelly or flatpak are covered
# without any extra step. Tap-qualified names (owner/tap/name), Homebrew-only
# options (--cask, --greedy, --json, ...) and every other subcommand go to
# Homebrew unchanged, and scripts that call brew are unaffected.

_linux_formulas_app_option() {
    case "$1" in
        -y|--yes|--non-interactive|--dry-run|--native|--rpm|--dnf|--pacman|--aur|--flatpak|--flathub|--brew|--appimage|--archive|--backend=*) return 0 ;;
        *) return 1 ;;
    esac
}

brew() {
    local subcommand="${1:-}"
    case "$subcommand" in
        install|upgrade|uninstall|remove|rm|list|ls|outdated|info|search) ;;
        *) command brew "$@"; return ;;
    esac

    local -a names=() app_options=() homebrew_options=()
    local arg
    for arg in "${@:2}"; do
        if [[ "$arg" != -* ]]; then
            names+=("$arg")
        elif _linux_formulas_app_option "$arg"; then
            app_options+=("$arg")
        else
            homebrew_options+=("$arg")
        fi
    done
    # Homebrew-specific options mean the caller wants Homebrew itself.
    if (( ${#homebrew_options[@]} )); then
        command brew "$@"
        return
    fi

    case "$subcommand" in
        list|ls|outdated)
            # `brew list gh` shows a keg's files: that is Homebrew's job.
            if (( ${#names[@]} )); then command brew "$@"; else command brew app "$subcommand" "${app_options[@]}"; fi
            return ;;
        info|search)
            if (( ${#names[@]} == 1 )); then command brew app "$subcommand" "${names[0]}" "${app_options[@]}"; else command brew "$@"; fi
            return ;;
        upgrade)
            if (( ${#names[@]} == 0 )); then command brew app upgrade "${app_options[@]}"; return; fi ;;
        install) (( ${#names[@]} )) || { command brew "$@"; return; } ;;
        *) (( ${#names[@]} )) || { command brew "$@"; return; }; subcommand=uninstall ;;
    esac

    local status=0
    local -a qualified=()
    for arg in "${names[@]}"; do
        if [[ "$arg" == */* ]]; then
            qualified+=("$arg")
        else
            command brew app "$subcommand" "$arg" "${app_options[@]}" || status=$?
        fi
    done
    if (( ${#qualified[@]} )); then
        command brew "$subcommand" "${qualified[@]}" || status=$?
    fi
    return "$status"
}
