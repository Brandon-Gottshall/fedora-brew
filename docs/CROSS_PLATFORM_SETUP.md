# Cross-Platform Machine Setup & Brewfile Strategy

This document describes how to structure reproducible machine configurations across **Fedora Linux** and **macOS** using Homebrew and `linux-formulas`.

---

## 1. The Three-Layer Setup Architecture

To keep configuration clean and avoid mixing application packaging with personal dotfiles, maintain separation across three layers:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Personal Tap (linux-formulas / homebrew-linux-formulas) │
│  - Package formulas (antigravity.rb, etc.)                  │
│  - Formula tests, desktop bootstrap script, updaters        │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│  Layer 2: Machine Setup / Dotfiles Repository               │
│  - Installs Homebrew & shell configuration                  │
│  - Attaches personal tap & executes desktop bootstrap       │
│  - Runs DNF/Flatpak steps (Linux) & system defaults (macOS) │
│  - Orchestrates 'brew bundle'                               │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│  Layer 3: Declarative Brewfile                              │
│  - Declares standard CLI tools and GUI applications         │
│  - Dispatches to macOS Casks vs Linux Tap Formulas          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Declarative Cross-Platform Brewfile

Homebrew evaluates `Brewfile` files using Ruby, enabling platform conditionals directly within a single file or via split files.

### Recommended Single `Brewfile` Pattern:

```ruby
# Brewfile: Cross-platform declarations

# 1. Tap personal repository
tap "Brandon-Gottshall/linux-formulas", "https://github.com/Brandon-Gottshall/fedora-brew"

# 2. Universal CLI Tools (Linux & macOS)
brew "git"
brew "ripgrep"
brew "fd"
brew "jq"
brew "tmux"
brew "zoxide"
brew "fzf"

# 3. Graphical Applications
if OS.mac?
  # macOS: Use native Casks
  cask "antigravity"
  cask "ghostty"
  cask "visual-studio-code"
elsif OS.linux?
  # Linux: Use personal tap formulas for custom packages
  brew "Brandon-Gottshall/linux-formulas/antigravity"
end
```

> [!NOTE]
> **Fully Qualified Formula Names**:
> On Linux, always reference custom graphical formulas by their fully-qualified name (e.g. `Brandon-Gottshall/linux-formulas/antigravity`) to prevent naming collisions with upstream Homebrew formulas or macOS casks.

---

## 3. Recommended Fresh Machine Sequences

### On Fedora Linux:
```bash
# 1. Install Homebrew (Linuxbrew)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# 2. Attach personal tap
brew tap Brandon-Gottshall/linux-formulas https://github.com/Brandon-Gottshall/fedora-brew

# 3. Run desktop bootstrap once
"$(brew --prefix)/Homebrew/Library/Taps/brandon-gottshall/homebrew-linux-formulas/scripts/bootstrap-desktop"

# 4. Bundle software from Brewfile
brew bundle --file=~/dotfiles/Brewfile

# 5. Log out and log back in to activate desktop launchers
```

### On macOS:
```bash
# 1. Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2. Bundle software from Brewfile
brew bundle --file=~/dotfiles/Brewfile
```
