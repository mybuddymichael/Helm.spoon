# Helm

A Hammerspoon window management plugin that is easy to use and easy to modify.

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
    move_left = { { "alt" }, "h"},
    move_right = { { "alt" }, "l"},
    move_up = { { "alt" }, "k"},
    move_down = { { "alt" }, "j"},
})
helm:start()
```

## Development

Helm is intentionally created to be easy to modify. I encourage you to fork it and modify it as you see fit.

## License

MIT License
