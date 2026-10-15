#!/usr/bin/env python3
"""A UDP chaos proxy between an online game's clients and its host.

The online soak (tools/bin/net-soak) puts this between the headless
clients and the headless host to give real sockets a bad network: datagrams
lost, delayed, jittered, duplicated and reordered, and timed outages. Python
3.10, standard library only.

Every client that sends to the proxy's address gets a session of its own,
with its own upstream socket toward the host, so the host sees one peer per
client as it would without the proxy. --listen may be given several times
(the soak gives each client process a port of its own, so the report can
tell whose a session was: its "via" port). With --spread and an IPv4
loopback host, the sessions of the n-th listening port reach the host from
127.0.0.(n + 2): the host sees each client from an address of its own, as
machines on the internet, not all from one (its per-address limits would
take them for one machine's tries; IPv6 has a single loopback address).

Each direction of each session - "up" (client to host) and "down" (host to
client) - has its conditions and its own seeded random stream: with the
same seed the n-th datagram of a direction always meets the same fate. An
outage drops every datagram that arrives while it lasts, both ways, every
session. With --clean-for S everything passes untouched for the first S
seconds (joining over a good link), the conditions after.

A cap (--down-rate-kbit, --up-rate-kbit or --rate-kbit for both) models the
host's own line, shared by every session: "down" is the host's uplink -
everything it sends to every client together - and "up" its downlink. A
capped way is a token bucket at that rate (the IP and UDP headers counted:
28 bytes a datagram over IPv4, 48 over IPv6) with a queue in front of it
holding --queue-ms milliseconds at that rate (default 250); a datagram that
finds the queue full is dropped (tail drop, as a router's buffer). The host's
uplink comes before the network's conditions (a datagram waits its turn on
the line, then meets the delay and the loss: one lost on the way still took
its time on the line), its downlink after them. The cap holds from the start,
--clean-for or not: it is the host's line, not the network's weather.

The proxy counts, per session and direction, what it received, forwarded,
lost and duplicated (UDP payload bytes, which for the game are its DTLS
records: the IP and UDP headers - 28 bytes a datagram over IPv4, 48 over
IPv6 - come on top) and the busiest second; the totals' busiest seconds are
every session's together (the host's upload at its peak). It writes them as
JSON to --report at the end (SIGINT, SIGTERM, --duration), every
--report-every seconds, and when sent SIGUSR1.

    chaos_proxy.py --listen 127.0.0.1:42100 --upstream 127.0.0.1:42099 \\
        --loss 5 --delay 40 --jitter 30 --dup 2 --reorder 5 \\
        --outage 30:500 --outage-every 60:500 --seed 1 --report proxy.json

Conditions apply to both directions; --up-loss, --down-delay and so on set
one direction. With --control FILE they can change while it runs (net-mock's
ping, typed as you play): whenever the file changes it is read as JSON and
its "loss", "delay", "jitter", "dup", "reorder" (both ways; "up_delay",
"down_loss" ... one way; missing keys keep their values) replace them. Percentages are 0-100, times in milliseconds. A datagram's
delay is --delay plus up to --jitter (uniform, which reorders on its own);
with probability --reorder it is held back further (1 to delay + jitter + 20
ms), and with probability --dup a second copy goes with a delay of its own.
These are the in-process loopback's rules (game/src/net/net_loopback.gd).
Addresses: "127.0.0.1:42100", "[::1]:42100", or a host name with a port.

tools/net/test_chaos_proxy.py tests it.
"""

import argparse
import heapq
import json
import os
import random
import selectors
import signal
import socket
import sys
import time

BUFFER = 65535


def parse_endpoint(text):
    """(family, sockaddr) of "host:port" or "[v6]:port"."""
    text = text.strip()
    if text.startswith("["):
        host, sep, rest = text[1:].partition("]")
        if not sep or not rest.startswith(":"):
            raise ValueError("expected [address]:port: %r" % text)
        port_text = rest[1:]
    else:
        host, sep, port_text = text.rpartition(":")
        if not sep or not host or ":" in host:
            raise ValueError("expected address:port (an IPv6 address in brackets): %r" % text)
    if not port_text.isdigit() or not 0 <= int(port_text) <= 65535:
        raise ValueError("bad port: %r" % text)
    infos = socket.getaddrinfo(host, int(port_text), type=socket.SOCK_DGRAM)
    family, _, _, _, addr = infos[0]
    return family, addr


def format_addr(addr):
    host, port = addr[0], addr[1]
    return "[%s]:%d" % (host, port) if ":" in host else "%s:%d" % (host, port)


class Conditions:
    """One direction's conditions: loss, dup and reorder as fractions."""

    def __init__(self, loss=0.0, delay_ms=0, jitter_ms=0, dup=0.0, reorder=0.0):
        self.loss = loss
        self.delay_ms = delay_ms
        self.jitter_ms = jitter_ms
        self.dup = dup
        self.reorder = reorder

    def to_json(self):
        return {"loss_pct": self.loss * 100, "delay_ms": self.delay_ms, "jitter_ms": self.jitter_ms,
                "dup_pct": self.dup * 100, "reorder_pct": self.reorder * 100}


def apply_conditions(c, d, prefix=""):
    """Sets Conditions `c` from dictionary `d` - "loss", "delay", "jitter",
    "dup", "reorder" (percentages 0-100, milliseconds), each overridden by
    `prefix` + its name -; what `d` lacks stays."""
    for name in ("loss", "delay", "jitter", "dup", "reorder"):
        v = d.get(prefix + name, d.get(name))
        if v is None:
            continue
        if name in ("delay", "jitter"):
            setattr(c, name + "_ms", max(0, int(v)))
        else:
            setattr(c, name, _pct(float(v)))


class Outages:
    """Timed windows (seconds since the proxy started) when nothing passes:
    fixed ones and, optionally, one every `every_s` seconds lasting
    `every_ms`."""

    def __init__(self, windows=(), every_s=0.0, every_ms=0):
        self.windows = [(float(a), float(b)) for a, b in windows]
        self.every_s = float(every_s)
        self.every_ms = int(every_ms)

    def down(self, t):
        for a, b in self.windows:
            if a <= t < b:
                return True
        if self.every_s > 0 and self.every_ms > 0 and t >= self.every_s:
            return (t % self.every_s) < self.every_ms / 1000.0
        return False

    def to_json(self):
        return {"windows_s": self.windows, "every_s": self.every_s, "every_ms": self.every_ms}


class Link:
    """A capped line one way, shared by every session (the host's uplink or
    downlink): a token bucket at `rate_kbit` kilobits a second - each
    datagram counted with `overhead` bytes of IP and UDP headers - holding
    `burst` bytes at most, behind a first-in first-out queue that holds
    `queue_ms` milliseconds of the line's time. offer() tells when a
    datagram leaves the line, or that the queue was full (tail drop).

    The bucket is kept as a time: `free_at`, when the line has sent
    everything queued so far; the bucket is full once `free_at` lies
    `burst` bytes' time in the past."""

    def __init__(self, rate_kbit, queue_ms=250, overhead=28, burst=1500):
        self.rate_kbit = rate_kbit
        self.queue_ms = queue_ms
        self.overhead = overhead
        self.burst = burst
        self.rate = rate_kbit * 1000.0 / 8.0            # bytes a second
        self.free_at = -1e9
        self.counts = {"passed": 0, "passed_bytes": 0, "dropped": 0, "dropped_bytes": 0}
        self.wait_sum = 0.0
        self.wait_max = 0.0
        self.seconds = {}                                # the longest wait (ms) in each whole second

    def offer(self, t, size):
        """The wait in seconds (0: at once) of a datagram of `size` bytes
        (its UDP payload) arriving at `t`, or None when the queue is full:
        dropped."""
        cost = (size + self.overhead) / self.rate
        done = max(self.free_at, t - self.burst / self.rate) + cost
        wait = max(0.0, done - t)
        if wait > self.queue_ms / 1000.0 + cost + 1e-9:
            self.counts["dropped"] += 1
            self.counts["dropped_bytes"] += size
            return None
        self.free_at = done
        self.counts["passed"] += 1
        self.counts["passed_bytes"] += size
        self.wait_sum += wait
        self.wait_max = max(self.wait_max, wait)
        second = int(t)
        self.seconds[second] = max(self.seconds.get(second, 0.0), wait * 1000.0)
        return wait

    def to_json(self):
        d = {"rate_kbit": self.rate_kbit, "queue_ms": self.queue_ms, "overhead": self.overhead, "burst": self.burst}
        d.update(self.counts)
        offered = self.counts["passed"] + self.counts["dropped"]
        d["dropped_pct"] = round(100.0 * self.counts["dropped"] / offered, 2) if offered else 0.0
        d["wait_mean_ms"] = round(1000.0 * self.wait_sum / self.counts["passed"], 1) if self.counts["passed"] else 0.0
        d["wait_max_ms"] = round(1000.0 * self.wait_max, 1)
        # the seconds whose longest wait passed half the queue
        d["seconds_half_full"] = sum(1 for v in self.seconds.values() if v > self.queue_ms / 2.0)
        d["seconds"] = len(self.seconds)
        return d


class Direction:
    """One way of one session: its conditions, its random stream, its counts."""

    def __init__(self, conditions, rng):
        self.c = conditions
        self.rng = rng
        self.counts = {"packets": 0, "bytes": 0, "lost": 0, "outage": 0, "duplicated": 0, "reordered": 0,
                       "queue_full": 0, "forwarded": 0, "forwarded_bytes": 0, "errors": 0}
        self.first_s = None
        self.last_s = None
        self.seconds = {}

    def plan(self, t, size, down, clean=False, full=False):
        """The delays (ms) of the copies to send of a datagram of `size` bytes
        received at `t` (seconds since the start); [] when it is dropped
        (`down`: in an outage; `full`: the capped line's queue was full;
        `clean`: passed at once, untouched). Every datagram draws the same six
        numbers, so its fate depends only on its place in the direction's
        stream."""
        c = self.c
        self.counts["packets"] += 1
        self.counts["bytes"] += size
        if self.first_s is None:
            self.first_s = t
        self.last_s = t
        second = int(t)
        self.seconds[second] = self.seconds.get(second, 0) + size
        r = self.rng
        lose, jit, hold, extra, double, jit2 = (r.random(), r.random(), r.random(), r.random(), r.random(),
                                                r.random())
        if full:
            self.counts["queue_full"] += 1
            return []
        if clean:
            return [0]
        if down:
            self.counts["outage"] += 1
            return []
        if lose < c.loss:
            self.counts["lost"] += 1
            return []
        delay = c.delay_ms + int(jit * (c.jitter_ms + 1)) if c.jitter_ms > 0 else c.delay_ms
        if hold < c.reorder:
            delay += 1 + int(extra * (c.delay_ms + c.jitter_ms + 20))
            self.counts["reordered"] += 1
        out = [delay]
        if double < c.dup:
            out.append(c.delay_ms + int(jit2 * (c.jitter_ms + 1)) if c.jitter_ms > 0 else c.delay_ms)
            self.counts["duplicated"] += 1
        return out

    def sent(self, size):
        self.counts["forwarded"] += 1
        self.counts["forwarded_bytes"] += size

    def to_json(self):
        d = dict(self.counts)
        d["first_s"] = self.first_s
        d["last_s"] = self.last_s
        d["peak_bytes_per_s"] = max(self.seconds.values()) if self.seconds else 0
        return d


class Session:
    """One client: its address, the listening port it came to, its upstream
    socket, its two directions."""

    def __init__(self, number, client, via, family, upstream, up, down, seed, source=None):
        self.number = number
        self.client = client
        self.via = via
        self.sock = socket.socket(family, socket.SOCK_DGRAM)
        self.sock.setblocking(False)
        _big_buffer(self.sock)
        if source:
            self.sock.bind((source, 0))
        self.sock.connect(upstream)
        self.up = Direction(up, random.Random("%s/%d/up" % (seed, number)))
        self.down = Direction(down, random.Random("%s/%d/down" % (seed, number)))

    def to_json(self):
        return {"number": self.number, "client": format_addr(self.client), "via": self.via,
                "up": self.up.to_json(), "down": self.down.to_json()}


def _big_buffer(sock):
    """A larger receive buffer (as far as the system allows): bursts of a
    dozen clients' datagrams must not overflow it."""
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 21)
    except OSError:
        pass


class Proxy:
    def __init__(self, listen, upstream, up, down, outages=None, seed=1, report=None, report_every=0.0,
                 duration=0.0, spread=False, clean_for=0.0, links=None, control=None):
        """`listen`: one (family, sockaddr) or a list of them; `links`:
        {"up": Link, "down": Link}, either one or both (the host's capped
        line; none: no cap)."""
        self.clean_for = clean_for
        self.control = control
        self._control_seen = None
        self.links = {"up": None, "down": None}
        self.links.update(links or {})
        self.spread = spread and upstream[0] == socket.AF_INET and upstream[1][0].startswith("127.")
        if isinstance(listen, tuple):
            listen = [listen]
        self.upstream_family, self.upstream_addr = upstream
        self.up = up
        self.down = down
        self.outages = outages or Outages()
        self.seed = seed
        self.report_path = report
        self.report_every = report_every
        self.duration = duration
        self.sessions = {}
        self.stopping = False
        self.report_now = False
        self.socks = []
        for family, addr in listen:
            sock = socket.socket(family, socket.SOCK_DGRAM)
            if family == socket.AF_INET6:
                sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            _big_buffer(sock)
            sock.bind(addr)
            sock.setblocking(False)
            self.socks.append(sock)
        self.ports = [s.getsockname()[1] for s in self.socks]
        self.port = self.ports[0]
        self._heap = []
        self._seq = 0
        self._seconds = {"up": {}, "down": {}}      # every session's bytes by whole second
        self._start = time.monotonic()
        self._started_unix = time.time()

    def now(self):
        return time.monotonic() - self._start

    def check_control(self):
        """The control file read again when it changed: the conditions it
        gives replace these (every session's at once). True when they did."""
        if not self.control:
            return False
        try:
            seen = os.stat(self.control).st_mtime_ns
        except OSError:
            return False
        if seen == self._control_seen:
            return False
        self._control_seen = seen
        try:
            with open(self.control) as f:
                d = json.load(f)
        except (OSError, ValueError) as e:
            print("chaos_proxy: the control file can't be read: %s" % e, flush=True)
            return False
        if not isinstance(d, dict):
            return False
        apply_conditions(self.up, d, "up_")
        apply_conditions(self.down, d, "down_")
        print("chaos_proxy: now up %s, down %s" % (self.up.to_json(), self.down.to_json()), flush=True)
        return True

    def stop(self, *_):
        self.stopping = True

    def _schedule(self, direction, way, data, send):
        t = self.now()
        sec = self._seconds[way]
        sec[int(t)] = sec.get(int(t), 0) + len(data)
        # the host's uplink first: the datagram waits its turn on the line
        # (or finds its queue full), then meets the network; the host's
        # downlink comes after the network (_push's `link`)
        wait = 0.0
        link = self.links[way]
        if link is not None and way == "down":
            wait = link.offer(t, len(data))
        # (with --clean-for the network is good at first - joining - and
        # its conditions come later)
        delays = direction.plan(t, len(data), self.outages.down(t), t < self.clean_for, wait is None)
        for delay in delays:
            self._push(t + (wait or 0.0) + delay / 1000.0, direction, data, send, link if way == "up" else None)

    def _push(self, at, direction, data, send, link=None):
        """Sends `data` at `at` (seconds since the start) - through `link`
        first, when given: the line's wait, or its full queue, from then."""
        self._seq += 1
        heapq.heappush(self._heap, (at, self._seq, direction, data, send, link))

    def _session(self, listen, addr, selector):
        via = listen.getsockname()[1]
        s = self.sessions.get((via, addr))
        if s is None:
            source = "127.0.0.%d" % (2 + self.ports.index(via)) if self.spread else None
            s = Session(len(self.sessions) + 1, addr, via, self.upstream_family, self.upstream_addr, self.up,
                        self.down, self.seed, source)
            self.sessions[(via, addr)] = s
            selector.register(s.sock, selectors.EVENT_READ, s)
        return s

    def run(self):
        selector = selectors.DefaultSelector()
        for sock in self.socks:
            selector.register(sock, selectors.EVENT_READ, sock)
        next_report = self.report_every if self.report_every > 0 else None
        next_control = 0.0
        try:
            while not self.stopping:
                t = self.now()
                if t >= next_control:
                    next_control = t + 0.25
                    self.check_control()
                if self.duration > 0 and t >= self.duration:
                    break
                wait = 0.25
                if self._heap:
                    wait = min(wait, max(0.0, self._heap[0][0] - t))
                for key, _ in selector.select(wait):
                    if isinstance(key.data, Session):
                        self._read_upstream(key.data)
                    else:
                        self._read_clients(key.data, selector)
                t = self.now()
                while self._heap and self._heap[0][0] <= t:
                    at, _, direction, data, send, link = heapq.heappop(self._heap)
                    if link is not None:
                        # the host's downlink: from here the datagram waits its turn
                        wait = link.offer(at, len(data))
                        if wait is None:
                            direction.counts["queue_full"] += 1
                        elif wait > 0:
                            self._push(at + wait, direction, data, send)
                        if wait is None or wait > 0:
                            continue
                    try:
                        send(data)
                        direction.sent(len(data))
                    except OSError:
                        direction.counts["errors"] += 1
                if next_report is not None and t >= next_report:
                    next_report += self.report_every
                    self.write_report()
                if self.report_now:
                    self.report_now = False
                    self.write_report()
        finally:
            self.write_report()
            for s in self.sessions.values():
                s.sock.close()
            for sock in self.socks:
                sock.close()

    def _read_clients(self, listen, selector):
        while True:
            try:
                data, addr = listen.recvfrom(BUFFER)
            except (BlockingIOError, InterruptedError):
                return
            except OSError:
                continue
            s = self._session(listen, addr, selector)
            self._schedule(s.up, "up", data, s.sock.send)

    def _read_upstream(self, s):
        while True:
            try:
                data = s.sock.recv(BUFFER)
            except (BlockingIOError, InterruptedError):
                return
            except OSError:
                # the host's port closed (ICMP unreachable): nothing to forward
                s.down.counts["errors"] += 1
                return
            listen = self.socks[self.ports.index(s.via)]
            self._schedule(s.down, "down", data, lambda d, c=s.client, l=listen: l.sendto(d, c))

    def report(self):
        sessions = [s.to_json() for s in self.sessions.values()]
        totals = {}
        for way in ("up", "down"):
            tot = {}
            for s in sessions:
                for k, v in s[way].items():
                    if isinstance(v, int) and k != "peak_bytes_per_s":
                        tot[k] = tot.get(k, 0) + v
            tot["peak_bytes_per_s"] = max(self._seconds[way].values()) if self._seconds[way] else 0
            # the five busiest seconds: [second since the start, bytes]
            tot["busiest_seconds"] = sorted(self._seconds[way].items(), key=lambda kv: -kv[1])[:5]
            totals[way] = tot
        return {"listen": [format_addr(s.getsockname()) for s in self.socks if s.fileno() >= 0],
                "upstream": format_addr(self.upstream_addr), "seed": self.seed,
                "conditions": {"up": self.up.to_json(), "down": self.down.to_json(),
                               "outages": self.outages.to_json()},
                "links": {way: link.to_json() for way, link in self.links.items() if link is not None},
                "clean_for_s": self.clean_for, "started_unix": self._started_unix, "elapsed_s": round(self.now(), 3),
                "cpu_s": round(time.process_time(), 3), "sessions": sessions, "totals": totals}

    def write_report(self):
        if not self.report_path:
            return
        tmp = self.report_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.report(), f, indent=1)
        os.replace(tmp, self.report_path)


def _pct(v):
    return max(0.0, min(100.0, float(v))) / 100.0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--listen", required=True, action="append",
                   help="where clients send: ADDRESS:PORT or [V6]:PORT (repeatable)")
    p.add_argument("--upstream", required=True, help="the host: ADDRESS:PORT or [V6]:PORT")
    for way in ("", "up-", "down-"):
        p.add_argument("--%sloss" % way, type=float, default=None, metavar="PCT")
        p.add_argument("--%sdelay" % way, type=int, default=None, metavar="MS")
        p.add_argument("--%sjitter" % way, type=int, default=None, metavar="MS")
        p.add_argument("--%sdup" % way, type=float, default=None, metavar="PCT")
        p.add_argument("--%sreorder" % way, type=float, default=None, metavar="PCT")
        p.add_argument("--%srate-kbit" % way, type=float, default=None, metavar="KBIT",
                       help=None if way else "cap the host's line (both ways; --down-rate-kbit: its uplink, what "
                       "it sends to every client together; --up-rate-kbit: its downlink), kilobits a second")
        p.add_argument("--%squeue-ms" % way, type=int, default=None, metavar="MS",
                       help=None if way else "a capped line's queue, in milliseconds at its rate (default 250)")
    p.add_argument("--outage", action="append", default=[], metavar="AT_S:MS",
                   help="nothing passes for MS milliseconds from AT_S seconds (repeatable)")
    p.add_argument("--outage-every", default="", metavar="S:MS", help="an outage of MS every S seconds")
    p.add_argument("--seed", default="1")
    p.add_argument("--report", default="", help="the JSON report's file")
    p.add_argument("--report-every", type=float, default=0.0, metavar="S")
    p.add_argument("--duration", type=float, default=0.0, metavar="S", help="stop after S seconds (0: never)")
    p.add_argument("--clean-for", type=float, default=0.0, metavar="S",
                   help="everything passes untouched for the first S seconds (joining), the conditions after")
    p.add_argument("--control", default="", metavar="FILE",
                   help="a JSON file read again whenever it changes: its loss, delay, jitter, dup, reorder (and "
                   "up_... / down_...) replace the conditions while the proxy runs")
    p.add_argument("--spread", action="store_true",
                   help="IPv4 loopback: each listening port's sessions from an address of their own")
    a = p.parse_args(argv)

    def conditions(way):
        def get(name, default):
            v = getattr(a, (way + name).replace("-", "_"))
            if v is None:
                v = getattr(a, name)
            return default if v is None else v
        return Conditions(_pct(get("loss", 0)), max(0, get("delay", 0)), max(0, get("jitter", 0)),
                          _pct(get("dup", 0)), _pct(get("reorder", 0)))

    windows = []
    for o in a.outage:
        at, _, ms = o.partition(":")
        windows.append((float(at), float(at) + float(ms) / 1000.0))
    every_s, every_ms = 0.0, 0
    if a.outage_every:
        s, _, ms = a.outage_every.partition(":")
        every_s, every_ms = float(s), int(ms)
    upstream = parse_endpoint(a.upstream)
    links = {}
    for way in ("up", "down"):
        def get(name, default):
            v = getattr(a, (way + "_" + name))
            if v is None:
                v = getattr(a, name)
            return default if v is None else v
        if get("rate_kbit", 0) > 0:
            links[way] = Link(get("rate_kbit", 0), max(0, get("queue_ms", 250)),
                              48 if upstream[0] == socket.AF_INET6 else 28)
    proxy = Proxy([parse_endpoint(x) for x in a.listen], upstream, conditions("up-"), conditions("down-"),
                  Outages(windows, every_s, every_ms), a.seed, a.report or None, a.report_every, a.duration,
                  a.spread, a.clean_for, links, a.control or None)
    signal.signal(signal.SIGTERM, proxy.stop)
    signal.signal(signal.SIGINT, proxy.stop)
    if hasattr(signal, "SIGUSR1"):
        signal.signal(signal.SIGUSR1, lambda *_: setattr(proxy, "report_now", True))
    print("chaos_proxy: %s -> %s (up %s, down %s, capped %s)" % (
          " ".join(format_addr(s.getsockname()) for s in proxy.socks), format_addr(proxy.upstream_addr),
          proxy.up.to_json(), proxy.down.to_json(),
          {w: "%g kbit/s, %d ms" % (k.rate_kbit, k.queue_ms) for w, k in links.items()} or "no"), flush=True)
    proxy.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
