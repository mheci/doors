# Doors — scheduler (scx) control
alias s := status

# Show scheduler status
status:
    scxctl status || scx_loader --help >/dev/null 2>&1

# Start a scheduler (default: scx_lavd)
start sched="lavd":
    scxctl start {{ sched }}

# Stop the scheduler
stop:
    scxctl stop

# Switch default scheduler permanently (lavd | bpfland | rusty | flash)
set-default sched="lavd":
    sudo scxctl set {{ sched }}

# Interactive TUI
tui:
    scxtui
