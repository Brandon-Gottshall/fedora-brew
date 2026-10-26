# shellcheck shell=bash
# Linux Formulas front end for Homebrew; source it from your shell profile.
#
#   brew install NAME    `brew app install NAME`: the tap catalog first (with
#                        aliases), then an exact Homebrew formula/Linux cask,
#                        then exact matches on Flathub, pacman, the AUR and
#                        GitHub release AppImages/archives (confirmed first).
#   brew upgrade         Homebrew, then every Flatpak app and runtime, then
#                        everything `brew app` manages, so every install
#                        method stays updatable from one command.
#   brew upgrade NAME    `brew app upgrade NAME`, which hands packages it does
#                        not manage back to Homebrew.
#
# Tap-qualified names (owner/tap/name), Homebrew-only options (--cask, --HEAD,
# ...) and every other subcommand go to Homebrew unchanged.

_linux_formulas_app_option() {
    case "$1" in
        -y|--yes|--non-interactive|--dry-run|--native|--rpm|--dnf|--pacman|--aur|--flatpak|--flathub|--appimage|--archive|--backend=*) return 0 ;;
        *) return 1 ;;
    esac
}

_linux_formulas_upgrade_everything() {
    local status=0 dry_run= arg
    local -a homebrew_args=()
    for arg; do
        case "$arg" in
            -n|--dry-run) dry_run=1; homebrew_args+=("$arg") ;;
            -y|--yes|--non-interactive) ;;
            *) homebrew_args+=("$arg") ;;
        esac
    done

    command brew upgrade "${homebrew_args[@]}" || status=$?
    if command -v flatpak >/dev/null 2>&1; then
        if [[ -n "$dry_run" ]]; then
            echo "==> Flatpak updates that would be installed:"
            flatpak remote-ls --updates || status=$?
        else
            echo "==> Upgrading Flatpak apps and runtimes"
            flatpak update -y || status=$?
        fi
    fi
    command brew app upgrade ${dry_run:+--dry-run} || status=$?
    return "$status"
}

brew() {
    local subcommand="${1:-}"
    if [[ "$subcommand" != install && "$subcommand" != upgrade ]]; then
        command brew "$@"
        return
    fi

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

    if [[ "$subcommand" == upgrade && ${#names[@]} -eq 0 ]]; then
        _linux_formulas_upgrade_everything "${@:2}"
        return
    fi
    # Homebrew-specific options mean the caller wants Homebrew itself.
    if (( ${#homebrew_options[@]} )) || (( ${#names[@]} == 0 )); then
        command brew "$@"
        return
    fi

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
