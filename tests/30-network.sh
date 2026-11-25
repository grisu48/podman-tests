#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# Networking: bridge networks, addresses, reachability, name resolution,
# isolation between networks and published ports on the host.

serve_payload() {	# minimal service inside a busybox container
	printf 'mkdir -p /www; echo -n payload > /www/index.html; httpd -f -p 8080 -h /www'
}

# pick_free_port: a connection that fails means the port is free.
pick_free_port() {
	local tries=20 p
	while [ "$tries" -gt 0 ] ; do
		p=$(( (RANDOM % 16384) + 20000 ))
		if ! curl --silent --show-error --connect-timeout 1 --max-time 2 \
			"http://127.0.0.1:$p/" >/dev/null 2>&1 ; then
			printf '%s' "$p" ; return 0
		fi
		tries=$(( tries - 1 ))
	done
	log "no free port in 20000..36383 after 20 tries" ; return 1
}

# wait_http: bounded retry so a starting listener is not mistaken for a
# broken mapping.
wait_http() { # <url> [tries]
	local url=$1 tries=${2:-8}
	while : ; do
		if curl --fail --silent --show-error --connect-timeout 2 \
			--max-time 10 "$url" >/dev/null 2>&1 ; then return 0 ; fi
		tries=$(( tries - 1 ))
		[ "$tries" -le 0 ] && { log "http kept failing: $url" ; return 1 ; }
		sleep 1
	done
}

http_code() {	# <url> — the HTTP status on stdout
	curl --fail --silent --show-error --output /dev/null \
		--write-out '%{http_code}' --connect-timeout 5 --max-time 15 "$1"
}

http_body() {	# <url> — the response body on stdout
	curl --fail --silent --show-error \
		--connect-timeout 5 --max-time 15 "$1"
}

container_ip() {	# <name> — the container's non-loopback IPv4
	eng exec "$1" ip -o -4 addr show
	awk '/inet/ && $4 !~ /^127\./ { gsub(/\/.*/, "", $4); print $4; exit }' \
		<<<"$LAST_OUT"
}

fetch_from_network() {	# <network> <target> — bounded client attempt
	local n=$1 target=$2 tries=8
	while [ "$tries" -gt 0 ] ; do
		if engine run --rm --network "$n" "$IMAGE_BUSYBOX" \
			wget -T 5 -qO- "http://$target:8080/" ; then
			return 0
		fi
		tries=$(( tries - 1 ))
		sleep 1
	done
	log "client never connected to $target on $n"
	return 1
}

test_network_bridge_create() {
	local n
	n=$(mkname net-create)
	eng network create "$n"
	add_cleanup network "$n"
	eng network ls
	assert_match "$n .*bridge|bridge.*$n" "$LAST_OUT" \
		"the network is listed with driver bridge"
	quiet network rm "$n"
}

test_network_container_ip() {
	local n c ip
	n=$(mkname net-ip)
	eng network create "$n"
	add_cleanup network "$n"
	c=$(mkname net-ip-c)
	RUNFLAGS=(--network "$n") && start_bg "$c" sleep 300
	ip=$(container_ip "$c")
	assert_match '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' "$ip" \
		"a non-loopback interface carries an IPv4 address"
	eng inspect --format "{{(index .NetworkSettings.Networks \"$n\").IPAddress}}" "$c"
	assert_eq "$ip" "$LAST_OUT" "the engine reports the same address"
}

test_network_container_to_container() {
	local n cl ip
	n=$(mkname net-c2c)
	eng network create "$n"
	add_cleanup network "$n"
	cl=$(mkname net-listener)
	RUNFLAGS=(--network "$n") && start_bg "$cl" sh -c "$(serve_payload)"
	ip=$(container_ip "$cl")
	assert_ok "the payload arrives over the bridge by address" \
		fetch_from_network "$n" "$ip"
	assert_eq payload "$LAST_OUT" "the payload is unchanged"
}

test_network_name_resolution() {
	local n cl
	n=$(mkname net-dns)
	eng network create "$n"
	add_cleanup network "$n"
	cl=$(mkname net-listener)
	RUNFLAGS=(--network "$n") && start_bg "$cl" sh -c "$(serve_payload)"
	assert_ok "the peer is reachable by container name" \
		fetch_from_network "$n" "$cl"
	assert_eq payload "$LAST_OUT" "the payload is unchanged"
	assert_fail "an unknown name does not resolve" \
		engine run --rm --network "$n" "$IMAGE_BUSYBOX" \
			wget -T 5 -qO- "http://no-such-container.invalid/"
}

test_network_isolation() {
	local n1 n2 cl ip
	n1=$(mkname net-iso-a)
	n2=$(mkname net-iso-b)
	eng network create "$n1"
	add_cleanup network "$n1"
	eng network create "$n2"
	add_cleanup network "$n2"
	cl=$(mkname net-listener)
	RUNFLAGS=(--network "$n1") && start_bg "$cl" sh -c "$(serve_payload)"
	ip=$(container_ip "$cl")
	assert_fail "a container on another network does not connect" \
		engine run --rm --network "$n2" "$IMAGE_BUSYBOX" \
			wget -T 5 -qO- "http://$ip:8080/"
}

test_port_publish() {
	local p p2 c unpub
	p=$(pick_free_port) || skip_test "no free host port found"
	p2=$(pick_free_port) || skip_test "no free host port found"
	c=$(mkname net-pub)
	RUNFLAGS=(-p "127.0.0.1:$p:8080") && start_bg "$c" sh -c "$(serve_payload)"
	assert_ok "the host reaches the published port" \
		wait_http "http://127.0.0.1:$p/"
	assert_eq 200 "$(http_code "http://127.0.0.1:$p/")" \
		"the published port answers with status 200"
	assert_eq payload "$(http_body "http://127.0.0.1:$p/")" \
		"the body is the content the container serves"
	eng port "$c"
	assert_match "127.0.0.1:$p" "$LAST_OUT" "the engine reports the mapping"

	# a port that was never published must not answer
	unpub=$(mkname net-unpub)
	start_bg "$unpub" sh -c "$(serve_payload)"
	assert_fail "an unpublished port is not reachable" \
		curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
			"http://127.0.0.1:$p2/"
}

test_port_release() {
	local p c d
	p=$(pick_free_port) || skip_test "no free host port found"
	c=$(mkname net-release)
	RUNFLAGS=(-p "127.0.0.1:$p:8080") && start_bg "$c" sh -c "$(serve_payload)"
	assert_ok "the published port is reachable" wait_http "http://127.0.0.1:$p/"
	quiet rm -f "$c"
	assert_fail "the formerly published port is closed" \
		curl --fail --silent --show-error --connect-timeout 2 --max-time 4 \
			"http://127.0.0.1:$p/"
	d=$(mkname net-release2)
	assert_ok "a new container publishes the same port again" \
		engine run -d --name "$d" -p "127.0.0.1:$p:8080" "$IMAGE_BUSYBOX" \
			sh -c "$(serve_payload)"
	add_cleanup container "$d"
	quiet rm -f "$d"
}
