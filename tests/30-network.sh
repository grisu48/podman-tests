# SPDX-License-Identifier: MIT
# Bridge networks: addressing, reachability, name resolution, isolation,
# port publishing.

# The opensuse/busybox image is built without the httpd applet, so the
# listener role uses the opensuse/nginx image instead: seed its default
# docroot with the fixed payload, then exec nginx itself as the container's
# main process on its default port.
SERVER_CMD='echo cetest-ok > /srv/www/htdocs/index.html && exec nginx -g "daemon off;"'

start_listener() {
  run_bg "$2" --network "$1" "$IMAGE_NGINX" sh -c "$SERVER_CMD"
}

free_port() {
  local p=20000
  while [ "$p" -lt 20100 ]; do
    if ! curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$p/" 2>/dev/null; then
      echo "$p"
      return 0
    fi
    p=$((p + 1))
  done
  return 1
}

test_bridge_network_create() {
  local n; n=$(rname net1); track network "$n"
  engine network create --driver bridge "$n"
  assert_ok "network create" "$LAST_STATUS" || return 1
  engine network ls --format '{{.Name}} {{.Driver}}'
  assert_contains "listed with driver bridge" "$n bridge" "$LAST_OUT" || return 1
}

test_container_interface() {
  local n c addr; n=$(rname net-if); track network "$n"; c=$(rname net-if-c); track container "$c"
  engine network create --driver bridge "$n"
  run_bg "$c" --network "$n" "$IMAGE_BUSYBOX" sleep 300 || { fail_result "precondition running" running "$LAST_OUT"; return 1; }
  engine exec "$c" sh -c "ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -n1"
  assert_ok "read interface address" "$LAST_STATUS" || return 1
  addr=$LAST_OUT
  if [ -z "$addr" ] || [ "$addr" = "127.0.0.1" ]; then
    fail_result "non-loopback address" "an IPv4 address" "$addr"
    return 1
  fi
  engine inspect "$c" --format "{{(index .NetworkSettings.Networks \"$n\").IPAddress}}"
  assert_eq "engine reports same address" "$addr" "$LAST_OUT" || return 1
}

test_reachability_and_name_resolution() {
  local n l; n=$(rname net-reach); track network "$n"; l=$(rname net-reach-l); track container "$l"
  engine network create --driver bridge "$n"
  start_listener "$n" "$l" || { fail_result "listener running" running "$LAST_OUT"; return 1; }
  engine inspect "$l" --format "{{(index .NetworkSettings.Networks \"$n\").IPAddress}}"
  local ip=$LAST_OUT

  engine run --rm --network "$n" "$IMAGE_BUSYBOX" wget -q -T 5 -O - "http://$ip:80/"
  assert_ok "connect by address" "$LAST_STATUS" || return 1
  assert_eq "payload received unchanged" cetest-ok "$LAST_OUT" || return 1

  engine run --rm --network "$n" "$IMAGE_BUSYBOX" wget -q -T 5 -O - "http://$l:80/"
  assert_ok "connect by name" "$LAST_STATUS" || return 1
  assert_eq "payload by name unchanged" cetest-ok "$LAST_OUT" || return 1

  engine run --rm --network "$n" "$IMAGE_BUSYBOX" wget -q -T 5 -O - "http://no-such-$l:80/"
  assert_fail "unknown name does not resolve" "$LAST_STATUS" || return 1
}

test_network_isolation() {
  local n1 n2 l; n1=$(rname net-iso-1); track network "$n1"; n2=$(rname net-iso-2); track network "$n2"
  l=$(rname net-iso-l); track container "$l"
  engine network create --driver bridge "$n1"
  engine network create --driver bridge "$n2"
  start_listener "$n1" "$l" || { fail_result "listener running" running "$LAST_OUT"; return 1; }
  engine run --rm --network "$n2" "$IMAGE_BUSYBOX" wget -q -T 5 -O - "http://$l:80/"
  assert_fail "cross-network connection refused" "$LAST_STATUS" || return 1
}

test_port_publishing() {
  local c port status body; c=$(rname net-pub); track container "$c"
  port=$(free_port) || { fail_result "free port" "an available port" "none found"; return 1; }
  engine run -d --name "$c" -p "127.0.0.1:${port}:80" "$IMAGE_NGINX" sh -c "$SERVER_CMD"
  wait_for_state "$c" running 10 || { fail_result "precondition running" running "$LAST_OUT"; return 1; }

  if body=$(curl -s --fail --connect-timeout 2 --max-time 5 -w '\n%{http_code}' "http://127.0.0.1:${port}/" 2>/dev/null); then
    status=${body##*$'\n'}
    body=${body%$'\n'*}
    body=${body%$'\n'}
  else
    status=000
    body=""
  fi
  assert_eq "published port status" 200 "$status" || return 1
  assert_eq "published port body" cetest-ok "$body" || return 1
  engine port "$c"
  assert_match "engine reports the mapping" "80/tcp.*${port}" "$LAST_OUT" || return 1

  local other; other=$(free_port) || { fail_result "second free port" "an available port" "none found"; return 1; }
  if curl -s -o /dev/null --connect-timeout 2 --max-time 5 "http://127.0.0.1:${other}/"; then
    fail_result "unpublished port unreachable" "connection refused" "connected"
    return 1
  fi

  engine rm -f "$c"
  assert_ok "stop and remove" "$LAST_STATUS" || return 1
  if curl -s -o /dev/null --connect-timeout 2 --max-time 5 "http://127.0.0.1:${port}/"; then
    fail_result "port free after stop" "connection refused" "connected"
    return 1
  fi
  local c2; c2=$(rname net-pub-2); track container "$c2"
  engine run -d --name "$c2" -p "127.0.0.1:${port}:80" "$IMAGE_NGINX" sh -c "$SERVER_CMD"
  assert_ok "host port reusable once free" "$LAST_STATUS" || return 1
}
