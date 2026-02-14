# PasarGuard Multi-Panel

Run multiple [PasarGuard](https://github.com/PasarGuard/panel) panels on a single server — each with its own name, port, database and CLI command.

This script **does not modify** the original PasarGuard code. It downloads the official script, assigns a unique name and paths, and installs it as a standalone CLI command.

---

# Quick Start

```bash
bash <(curl -sSL https://raw.githubusercontent.com/D-7J/pasarguard-multi-panel/main/install.sh)         
```
This opens an interactive menu where you choose panel name, port, and database.

---

# Install with Parameters


## Panel 1 — SQLite on port 8001
```bash
bash <(curl -sSL https://raw.githubusercontent.com/D-7J/pasarguard-multi-panel/main/install.sh) install --name panel1 --panel-port 8001 --database sqlite
```

## Panel 2 — MariaDB on port 8002 (DB on 3307)
```bash
bash <(curl -sSL https://raw.githubusercontent.com/D-7J/pasarguard-multi-panel/main/install.sh) install --name panel2 --panel-port 8002 --database mariadb --db-port 3307
```

## Panel 3 — MySQL on port 8003 (DB on 3308)
```bash
bash <(curl -sSL https://raw.githubusercontent.com/D-7J/pasarguard-multi-panel/main/install.sh) install --name panel3 --panel-port 8003 --database mysql --db-port 3308
```
# Install Options  
| Option         | Description                                      | Default              |
|:--------------:|:------------------------------------------------:|:--------------------:|
| `--name`       | Panel name (used as CLI command)                 | (asked interactively)|
| `--panel-port` | Web panel port                                   |                 8000 |
| `--database`   | sqlite / mariadb / mysql                         |               sqlite |
| `--db-port`    | Database port                                    |                 3306 |
| `--version`    | PasarGuard version tag                           |               latest |
| `--dev`        | Use dev version                                  |                    — |


After Installation
Each panel gets its own CLI command:
```text
panel1 help            # Show all commands
panel1 status          # Check if running
panel1 up              # Start
panel1 down            # Stop
panel1 restart         # Restart
panel1 logs            # View logs
panel1 tui             # Full TUI interface
panel1 node            # Node management
panel1 backup          # Manual backup
panel1 backup-service  # Auto backup to Telegram
panel1 core-update     # Change Xray core
panel1 edit            # Edit docker-compose.yml
panel1 edit-env        # Edit .env file
panel1 cli             # Panel CLI
panel1 update          # Update panel
panel1 uninstall       # Remove panel
```
All original PasarGuard commands work — nothing is removed or changed.

---

## List Installed Panels
```bash
bash <(curl -sSL https://raw.githubusercontent.com/D-7J/pasarguard-multi-panel/main/install.sh) list         
```

Output:

  ● panel1 (port: 8001) - Running  
  ● panel2 (port: 8002) - Running  
  ○ panel3 (port: 8003) - Stopped  
  
How It Works

install.sh  
  ├── Downloads the official PasarGuard script  
  ├── Changes only: APP_NAME + file paths  
  ├── Installs as /usr/local/bin/<panel-name>  
  ├── Runs the original install command  
  └── Patches ports in .env and docker-compose.yml  

Each panel gets:  
```markdown
  /opt/<name>/             ← app config  
  /var/lib/<name>/         ← data + database  
  /usr/local/bin/<name>    ← CLI command  
```
    
No logic is modified. TUI, node management, backup, and every feature of the original script works as-is.

Port Planning Example
| Panel | Web Port	| DB Port	Database |
|:-------:|:----------:|:-------------:|
|panel1| 8001	| SQLite |
| panel2	| 8002	| 3307	| MariaDB |
| panel3	| 8003	| 3308	| MySQL |
| panel4	| 8004	| 3309	| MariaDB |  

The installer warns you if a port is already in use.  

Requirements  
Linux (Ubuntu/Debian/CentOS/Fedora/Arch)  
Root access  
Docker (installed automatically if missing)  
# Credits  
[PasarGuard](https://github.com/PasarGuard/panel) — the original panel  
---
This repo only provides the multi-panel wrapper
