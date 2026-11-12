#!/usr/bin/env bats
# `zmx attach --min-window` and `--unset-min-window` on a session that already
# runs. `zmx attach` needs a tty, so each client here is a real `zmx attach`
# on a pty of the given size.

load test_helper

# pty_attach <rows> <cols> <hold_seconds> <attach args...>
pty_attach() {
  python3 - "$ZMX" "$@" 3>&- <<'PY'
import fcntl, os, select, struct, subprocess, sys, termios, time
zmx, rows, cols, hold, args = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), sys.argv[5:]
master, slave = os.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
# Inside a session `zmx attach` asks that session's client to switch instead.
env = {k: v for k, v in os.environ.items() if k != "ZMX_SESSION"}
proc = subprocess.Popen([zmx, "attach", *args], stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
os.close(slave)
end = time.time() + hold
while time.time() < end:
    if select.select([master], [], [], 0.1)[0]:
        try:
            os.read(master, 65536)
        except OSError:
            break
proc.terminate()
proc.wait()
PY
}

# The size the session's PTY has now, as "rows cols".
pty_size() { "$ZMX" history "$1" | grep -E '^SIZE [0-9]+ [0-9]+$' | tail -n 1; }

wait_for_size() {
  local name="$1" want="SIZE $2" i=0
  while (( i < 50 )); do
    [ "$(pty_size "$name")" = "$want" ] && return 0
    sleep 0.1
    (( i++ )) || true
  done
  echo "Timed out waiting for '$want' in session '$name', last: $(pty_size "$name")" >&2
  return 1
}

# Start a session whose command prints the PTY's size on every SIGWINCH. The
# words it prints are assembled at runtime, so the echoed command line can't be
# taken for them.
size_session() {
  "$ZMX" run "$1" -d bash -c 'trap "printf \"%s %s\n\" SIZE \"\$(stty size)\"" WINCH; printf "TRAP_%s\n" SET; while :; do sleep 0.1; done'
  wait_for_output "$1" "TRAP_SET"
}

@test "attach -w and --unset-min-window change a running session" {
  size_session test-mw

  # The session was created without --min-window: it follows its leader.
  pty_attach 50 200 30 test-mw &
  wait_for_size test-mw "50 200"

  # A smaller client without the flag changes nothing.
  pty_attach 30 100 1 test-mw
  [ "$(pty_size test-mw)" = "SIZE 50 200" ]

  # With -w the session shrinks to the smallest client, and stays that way
  # for a later client that does not repeat the flag.
  pty_attach 30 100 30 -w test-mw &
  wait_for_size test-mw "30 100"
  pty_attach 20 150 30 test-mw &
  wait_for_size test-mw "20 100"

  # --unset-min-window gives the leader its size back.
  pty_attach 40 120 1 --unset-min-window test-mw
  wait_for_size test-mw "50 200"

  kill %1 %2 %3 2>/dev/null || true
}

@test "attach -w from inside another session changes the session it names" {
  size_session test-mw-in
  "$ZMX" run test-mw-from -d sleep 30
  wait_for_session test-mw-from

  pty_attach 50 200 30 test-mw-in &
  wait_for_size test-mw-in "50 200"
  pty_attach 30 100 30 test-mw-in &
  sleep 0.5
  [ "$(pty_size test-mw-in)" = "SIZE 50 200" ]

  # Inside a session `zmx attach` only asks that session's client to switch,
  # so the flag has to reach the named session on its own.
  ZMX_SESSION=test-mw-from "$ZMX" attach -w test-mw-in
  wait_for_size test-mw-in "30 100"
  ZMX_SESSION=test-mw-from "$ZMX" attach --unset-min-window test-mw-in
  wait_for_size test-mw-in "50 200"

  kill %1 %2 2>/dev/null || true
}
