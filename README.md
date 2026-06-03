# do-sh

> Plain-English → shell command, powered by a local LLM. No cloud, no subscriptions, runs on cheap hardware.

By Ethan McCartney — https://github.com/Master-Pr0grammer/do-sh

```
ask list all files and their sizes
ask show disk usage of each folder here
ask find all .log files modified in the last 7 days
ask show which processes are using the most memory
```

## How it works

You type `ask` followed by what you want in plain English. A local LLM ([Unsloth LFM2.5-1.2B-Instruct Q8_0](https://huggingface.co/unsloth/LFM2.5-1.2B-Instruct-GGUF), ~1.3 GB) generates a shell command. Then:

- **Safe read-only commands** (`ls`, `find`, `df`, `grep`, etc.) — the command is extracted from the stream the moment it's generated, checked against the whitelist, and run immediately. Generation stops early; the explanation is never even computed.
- **Anything else** — the explanation streams in parallel while the safety check runs. By the time you're asked to approve, the explanation is already there. No second round-trip to the model.
- **Dangerous patterns** (`rm`, `dd`, `mkfs`, etc.) — hard blocked. Shown for manual review only, never run.

The model stays loaded in memory for **5 minutes** after last use, then unloads automatically. Follow-up commands within that window are nearly instant.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Master-Pr0grammer/do-sh/main/install.sh | bash
```

The script downloads a precompiled `llama.cpp` binary and the LFM2.5 Q8_0 model, then installs the `ask` command to `~/.local/bin`. Everything lives in `~/.local/share/do-tool` — no root required, no system files touched.

First run: ~2–4 seconds to load the model. Subsequent runs within 5 minutes: nearly instant.

## Requirements

- Ubuntu/Debian (x64)
- `unzip` and `python3` (`sudo apt install unzip python3`)
- ~1.5 GB free disk space
- ~1.4 GB free RAM (for the warm model)

## Usage examples

```bash
# Files
ask list all files recursively with sizes
ask show hidden files in this directory
ask find files larger than 100MB

# Disk & system
ask show disk usage of each folder sorted by size
ask show how much RAM is free
ask list running processes sorted by CPU usage

# Searching
ask find all python files changed in the last week
ask search for the word "error" in all log files here
ask show the last 50 lines of syslog

# Network
ask show what ports are open
ask show my local IP address
```

## How the streaming output works

The model is instructed to emit its response in a strict XML format:

```
<cmd>find . -name "*.log" -mtime -7</cmd>
<why>Lists log files modified within the last 7 days</why>
```

The `<cmd>` tag always comes first. The moment `</cmd>` appears in the token stream, the command is extracted and the safety check runs — without waiting for the explanation to finish. If the command is safe, generation is cancelled immediately and the command runs. If it needs approval, the `<why>` stream continues printing to the terminal in real time while you decide.

## Safe command list

These run without asking: `ls`, `ll`, `la`, `tree`, `cat`, `less`, `head`, `tail`, `wc`, `pwd`, `whoami`, `id`, `hostname`, `uname`, `date`, `uptime`, `df`, `du`, `free`, `find`, `grep`, `egrep`, `fgrep`, `rg`, `fd`, `ps`, `top`, `htop`, `echo`, `printf`, `stat`, `file`, `lsblk`, `lscpu`, `lspci`, `lsusb`, `ip`, `addr`, `ifconfig`, `netstat`, `ss`, `env`, `printenv`, `which`, `type`, `whereis`, `dmesg`, `journalctl`, `systemctl`, `ping`, `traceroute`, `sort`, `uniq`, `cut`, `awk`, `sed`, `tr`, `diff`

Everything else asks first. `rm`, `dd`, `mkfs`, `fdisk`, `parted`, pipe-to-shell patterns (`| bash`, `| sh`), and writes to `/dev/*` are always blocked.

## Uninstall

```bash
bash ~/.local/share/do-tool/uninstall.sh
```

## File layout

```
~/.local/
├── bin/
│   └── do
└── share/do-tool/
    ├── bin/
    │   └── llama-server
    ├── models/
    │   └── LFM2.5-1.2B-Instruct-Q8_0.gguf
    ├── daemon.sh       ← server lifecycle
    ├── reaper.sh       ← 5-min idle watchdog
    ├── uninstall.sh
    └── logs/
        └── server.log
```

Everything is local. Nothing leaves your machine.
