# Contributing to Fedora Brew

Thank you for contributing to `fedora-brew`! This repository maintains personal Homebrew formulae for self-contained Linux applications.

---

## 1. Ground Rules & Admission

Before creating a new formula or proposing changes, please review:
* [Package Admission & Ownership Policy](docs/ADMISSION_POLICY.md)
* [Step-by-Step SOP for Adding Packages](docs/ADDING_A_PACKAGE.md)
* [Formula Patterns & Archetypes](docs/FORMULA_PATTERNS.md)

### Key Rules:
1. **Homebrew Owns Its Payloads**: Never invoke `sudo dnf install` or `flatpak install` inside a formula.
2. **Immutable Artifacts & SHA-256**: All downloads must use HTTPS and pin SHA-256 hashes.
3. **Stable Desktop Paths**: Use `#{opt_bin}/<binary>` in `.desktop` files, not versioned Cellar paths.
4. **Disable Auto-Updaters**: Application-internal auto-updaters must be disabled to preserve Homebrew ownership.
5. **No GUI Launch in Tests**: `test do` blocks must not spawn interactive GUI windows.

---

## 2. Local Development & Testing

Run the full local validation suite before opening a pull request:

```bash
# 1. Run repository unit tests
python3 -m unittest discover -s test -p 'test_*.py'

# 2. Run shell & bootstrap integration tests
bash test/test_desktop_bootstrap.sh
bash test/test_formula.sh
bash test/test_migration.sh

# 3. Check formula Ruby syntax
brew ruby -- -c Formula/<formula>.rb

# 4. RuboCop style check
brew style Brandon-Gottshall/fedora-brew/<formula>

# 5. Strict Homebrew audit
brew audit --strict Brandon-Gottshall/fedora-brew/<formula>

# 6. Test formula installation & static assertions
brew install --build-from-source Brandon-Gottshall/fedora-brew/<formula>
brew test Brandon-Gottshall/fedora-brew/<formula>
```

---

## 3. Pull Request Checklist

When submitting a pull request:
- [ ] Added or updated formula in `Formula/<name>.rb`.
- [ ] Formula passes `brew audit --strict` and `brew style`.
- [ ] Desktop `.desktop` file validates with `desktop-file-validate`.
- [ ] Added unit tests in `test/` where applicable.
- [ ] Verified update automation or livecheck logic.
- [ ] Tested installation, execution, and uninstallation.
