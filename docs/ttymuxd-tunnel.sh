#!/usr/bin/env bash
# set -xe # Enable for debug
# Shoule we persist logs / config in $HOME/.config/ttydmux/ ?
export TTYDMUX_DIR=$HOME/.config/ttydmux
mkdir -p $TTYDMUX_DIR
# Logfiles collect both stderr and stdout from ttyd and tunnel
export TTYD_LOGFILE=$TTYDMUX_DIR/ttyd.log
export TUNNEL_LOGFILE=$TTYDMUX_DIR/tunnel.log

# Possibly presist this...
# https://www.man7.org/linux/man-pages/man8/wg.8.html#COMMANDS
# wg genkey :: Generates a random private key in base64 and prints it to standard output.
# You could save this to persist your url.
# By default, for safety let's generate it on the fly each time
export TUNNEL_WIREGUARD_KEY=$(wg genkey)
export TUNNEL_API_URL=http://try.ii.nz

# We install to /usr/local/bin... but on OSX it's not in the path by default
export PATH=/usr/local/bin:$PATH

# Usage ttydmux [start|stop]
ACTION=${1:-status}
case $ACTION in
  status)
      # List information about tmux
      tmux -L ii list-sessions
      tmux -L ii has-session -t ii
      tmux -L ii list-windows -t ii
      # Display how to connect to ttyd
      if [[ -e $TTYDMUX_DIR/ttyd.pid ]]
      then ps -p $(cat $TTYDMUX_DIR/ttyd.pid) 2>&1 > /dev/null && \
        echo Connect to ttyd locally via http://localhost:54321
      fi
      # Display how to connect to tunnel
      if [[ -e $TTYDMUX_DIR/tunnel.pid ]]
      then ps -p $(cat $TTYDMUX_DIR/tunnel.pid) 2>&1 > /dev/null && \
        grep "You can now connect" $HOME/.config/ttydmux/tunnel.log
      fi
      # Display how to connect to tmux directly
      tmux -L ii has-session -t ii && \
        echo Connect to tmux locally via: &&\
        echo tmux -L ii at
  ;;
  start)
    if $(tmux -L ii has-session -t ii)
    then echo "tmux session exists!"
    else tmux -L ii new -d -c $HOME -e TTYDMUX=true -s ii
    echo $! > $TTYDMUX_DIR/tmux.pid
    fi
    ttyd -p 54321 tmux -L ii at 2>&1 > $TTYD_LOGFILE &
    echo $! > $TTYDMUX_DIR/ttyd.pid
    echo ttyd logs are available in $TTYD_LOGFILE
    tunnel localhost:54321 2>&1 > $TUNNEL_LOGFILE &
    echo $! > $TTYDMUX_DIR/tunnel.pid
    echo tunnel logs are available in $TTYD_LOGFILE
    echo Connect to tmux locally via: &&\
    echo tmux -L ii at
  ;;
  stop)
    # we won't stop tmux... let's leave it
    if [[ -e $TTYDMUX_DIR/ttyd.pid ]]
    then kill `cat $TTYDMUX_DIR/ttyd.pid` && rm $TTYDMUX_DIR/ttyd.pid
    fi
    if [[ -e $TTYDMUX_DIR/tunnel.pid ]]
    then kill `cat $TTYDMUX_DIR/tunnel.pid` && rm $TTYDMUX_DIR/tunnel.pid
    fi
  ;;
esac

# Relevant docs for ttyd
# https://manpages.ubuntu.com/manpages/impish/man1/ttyd.1.html#options
#  -p, --port <port>
#    Port to listen (default: 7681, use 0 for random port)
# ii tmux sessions are export with ttyd on port 54321


# Relevant Docs for tmux
# https://man7.org/linux/man-pages/man1/tmux.1.html
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
