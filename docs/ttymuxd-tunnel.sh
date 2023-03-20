#!/usr/bin/env bash

# Shoule we persist logs / config in $HOME/.config/ttydmux/ ?
export TTYDMUX_DIR=$(mktemp -t ttydmux -d)
# Logfiles collect both stderr and stdout from ttyd and tunnel
export TTYD_LOGFILE=$TTYDMUX_DIR/ttyd.log
export TUNNEL_LOGFILE=$TTYDMUX_DIR/ttyd.log

# Possibly presist this...
# https://www.man7.org/linux/man-pages/man8/wg.8.html#COMMANDS
# wg genkey :: Generates a random private key in base64 and prints it to standard output.
# You could save this to persist your url.
# By default, for safety let's generate it on the fly each time
export TUNNEL_WIREGUARD_KEY=$(wg genkey)
export TUNNEL_API_URL=http://try.ii.nz

# Possibly use a temp folder for files / logs
# Background tmux with -L ii for the session
#
# -L socket-name
#   tmux stores the server socket in a directory under
#   TMUX_TMPDIR or /tmp if it is unset.  The default
#   socket is named default.  This option allows a
#   different socket name to be specified, allowing
#   several independent tmux servers to be run.  Unlike
#   -S a full path is not necessary: the sockets are all
#   created in a directory tmux-UID under the directory
#   given by TMUX_TMPDIR or in /tmp.  The tmux-UID
#   directory is created by tmux and must not be world
#   readable, writable or executable.
#
#   If the socket is accidentally removed, the SIGUSR1
#   signal may be sent to the tmux server process to
#   recreate it (note that this will fail if any parent
#   directories are missing).
#
# new-session [-AdDEPX] [-c start-directory] [-e environment] [-f flags] [-F format]
#   [-n window-name] [-s session-name] [-t group-name] [-x width] [-y height] [shell-command]
#   (alias: new)
#     Create a new session with name session-name.
#
#     The new session is attached to the current terminal unless
#      -d is given.  window-name and shell-command are the name of
#      and shell command to execute in the initial window.
tmux -L ii new -d -c $HOME -e TTYDMUX=true -n ii -s ii

# https://manpages.ubuntu.com/manpages/impish/man1/ttyd.1.html#options
#  -p, --port <port>
#    Port to listen (default: 7681, use 0 for random port)
# ii tmux sessions are export with ttyd on port 54321
ttyd -p 54321 tmux -L ii at 2>&1 > $TTYD_LOGFILE &
disown

echo ttyd logs are available in $TTYD_LOGFILE

tunnel localhost:54321 2>&1 > $TUNNEL_LOGFILE &

echo tunnel logs are available in $TTYD_LOGFILE
