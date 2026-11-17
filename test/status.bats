#!/usr/bin/env bats
# Program status reports (OSC 7501).
#
# A program tells its terminal what it is doing with OSC 7501, and the terminal
# keeps the last report of each id. Reports pass through zmx as they are sent;
# these tests pin what a terminal gets that attaches afterwards.

load test_helper

# attach_output <session>: raw bytes a client receives on attach.
attach_output() {
  python3 - "$ZMX_DIR" "$1" 3>&- <<'PY'
import os, select, socket, struct, sys, time
sock_dir, name = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(os.path.join(sock_dir, name))
payload = struct.pack("<HHHH", 24, 80, 0, 0)                      # ipc.Resize
s.sendall(struct.pack("<BBHI", 7, 1, 0, len(payload)) + payload)  # ipc.Header, Init
out, end = b"", time.time() + 0.5
while time.time() < end:
    if select.select([s], [], [], 0.05)[0]:
        out += s.recv(65536)
s.close()
sys.stdout.write(out.decode("latin-1"))
PY
}

@test "attach replays the reports sent before it" {
  # \033\134 is ST. The marker is assembled at runtime so the echoed command
  # line can't match it.
  "$ZMX" run test-status -d sh -c '
    printf "\033]7501;state=working:id=a:app=demo\033\134"
    printf "\033]7501;state=done:id=b:app=demo\007"
    printf "\033]7501;state=clear:id=a\007"
    printf "\033]7501;state=blocked:id=c/d:kind=question\033\134"
    printf "READY_%s\n" OK
    sleep 30'
  wait_for_output test-status "READY_OK"

  output=$(attach_output test-status)
  # Each record as it was sent, oldest first; the cleared one is gone.
  [[ "$output" == *$'\e]7501;state=done:id=b:app=demo\e\\\e]7501;state=blocked:id=c/d:kind=question\e\\'* ]]
  [[ "$output" != *$'\e]7501;state=working:id=a'* ]]
}

@test "attach replays nothing a finished command left unfinished" {
  # OSC 133;D marks the end of a command, as a shell integration sends it.
  "$ZMX" run test-status-end -d sh -c '
    printf "\033]7501;state=working:id=a\007"
    printf "\033]7501;state=error:id=b:msg=failed\007"
    printf "\033]133;D;1\007"
    printf "READY_%s\n" OK
    sleep 30'
  wait_for_output test-status-end "READY_OK"

  output=$(attach_output test-status-end)
  [[ "$output" == *$'\e]7501;state=error:id=b:msg=failed\e\\'* ]]
  [[ "$output" != *$'\e]7501;state=working:id=a'* ]]
}
