# Helm

A window management playground, using Hammerspoon.

(Very much in progress.)

## Installation

`git clone https://github.com/mybuddymichael/helm.git ~/.hammerspoon/Spoons/helm`

## Usage

Add this to your configuration at `~/.hammerspoon/init.lua`:

```lua
helm = hs.loadSpoon("helm")

```

## Configuration

```lua
helm:bindHotkeys({
    focusLeft = { { "alt" }, "h" },
    focusRight = { { "alt" }, "l" },
    moveWindowLeft = { { "alt", "shift" }, "h" },
    moveWindowRight = { { "alt", "shift" }, "l" },
    makeFullScreen = { { "alt", "shift" }, "return" },
})
helm:start()
```

## License

MIT License
