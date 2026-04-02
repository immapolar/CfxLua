<div align="center">

# **CfxLua**

![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen?style=for-the-badge)
![Lua](https://img.shields.io/badge/LuaGLM-5.4-blue?style=for-the-badge&logo=lua&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-orange?style=for-the-badge)

**A standalone CfxLua interpreter.**

*Because booting an FXServer just to test a 12-line script is insane.*

---

</div>

## The Problem

Testing a FiveM resource means spinning up a full FXServer — gigabytes of binaries,
30–60 seconds of boot time, a license key, and a `server.cfg` — just to run a script
that does one thing.

That's not a workflow. That's a punishment.

---

## The Solution

```bash
cfxlua script.lua
```

Done. Milliseconds. No server. No config. No bullshit.

**CfxLua** is a true standalone interpreter for the CfxLua dialect — the Lua variant
powering FiveM and RedM — built on the actual LuaGLM VM that FXServer uses internally.

---

## What's Supported

### ✅ Full Server-Side Parity

Everything a `server.lua` runs on FiveM, runs identically here:

- **LuaGLM 5.4** — `vec2/3/4`, `quat`, `matrix`, all CfxLua syntax extensions
(`+=`, `?.`, destructuring, ```joaat```, `defer`)
- **Scheduler** — `CreateThread`, `Wait`, `Citizen.SetTimeout`, `Citizen.Await`,
coroutine-based cooperative threading
- **Event system** — `AddEventHandler`, `TriggerEvent`, `TriggerServerEvent`,
`RemoveEventHandler`
- **Exports \& statebags** — full proxy table behavior
- **Convar system** — `GetConvar`, `GetConvarInt`
- **JSON / msgpack** — `json.encode`, `json.decode`, full msgpack
- **Resource context** — `GetCurrentResourceName()` returns the correct value


### ⚠️ Client/Game Engine Scope

This project is a standalone runtime layer and does not provide full GTA/FiveM client engine behavior.

---

## Installation

```bash
git clone https://github.com/immapolar/CfxLua.git
cd CfxLua
make
make install   # adds cfxlua to PATH
```

> **Prerequisites:** CMake 3.14+, C/C++ compiler toolchain, Git with submodule support.

---

## Usage

```bash
cfxlua script.lua
cfxlua --version
cfxlua -v
cfxlua --help
cfxlua -h
```


---

## CLI Reference

| Flag | Description |
| :-- | :-- |
| `--version` / `-v` | Print version and exit |
| `--help` / `-h` | Print usage and exit |
| `<script.lua>` | Execute a Lua script |
| `[arg1 arg2 ...]` | Pass extra arguments to script as `arg[...]` |


---

## Project Structure

```
CfxLua/
├── vm/                 # VM build output directory
├── runtime/
│   ├── bootstrap.lua   # Entry point
│   ├── scheduler.lua   # CreateThread / Wait / Citizen.*
│   ├── events.lua      # AddEventHandler / TriggerEvent / TriggerNetEvent
│   ├── citizen.lua     # Citizen.* namespace, exports, statebags
│   ├── stubs.lua       # Server-side stubbed natives
│   ├── json.lua        # dkjson (pure Lua)
│   └── msgpack.lua     # lua-MessagePack (pure Lua)
├── bin/
│   ├── cfxlua          # POSIX shell wrapper
│   ├── cfxlua.cmd      # Windows CMD launcher
│   └── cfxlua.ps1      # Windows PowerShell launcher
├── tests/
└── Makefile
```


---

## License

MIT © 2026 Polaris Naz

---

<div align="center">

<sub>The FiveM developer workflow, finally unchained.</sub>

</div>
