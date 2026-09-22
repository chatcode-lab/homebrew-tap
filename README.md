# Chatcode Labs Homebrew Tap

This tap contains Homebrew formulae maintained by
[Chatcode Labs](https://github.com/chatcode-lab).

## Install stock-tui

```bash
brew install chatcode-lab/tap/stock-tui
```

Homebrew updates the tap during `brew update`; install a newer release with:

```bash
brew upgrade stock-tui
```

To remove it:

```bash
brew uninstall stock-tui
```

In a `Brewfile`:

```ruby
tap "chatcode-lab/tap"
brew "stock-tui"
```

## Documentation

- [stock-tui](https://github.com/chatcode-lab/stock-tui)
- [Homebrew documentation](https://docs.brew.sh)

## Formula updates

The `stock-tui` formula uses the signed upstream binaries for macOS on Apple
Silicon and Intel, plus static Linux binaries for ARM64 and x86_64. A daily
workflow checks stable releases and validates all four archives against the
release checksum manifest and GitHub's asset metadata.

When a new version is available, the generated formula is installed and tested
on Apple Silicon macOS, Intel macOS, and Linux. Only after all three jobs pass
does the workflow commit the exact validated formula to `main`. The final push
is rejected if `main` changed during validation; the next scheduled run retries
from the new base. Maintainers can also start the workflow manually from the
Actions tab with the `main` branch selected. The optional `validate_current`
input runs the current formula through the same platform matrix without
publishing a change.

Future formula updates do not publish Homebrew bottles because the formula
already installs the verified upstream binaries directly.
