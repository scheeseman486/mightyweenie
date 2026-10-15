#!/usr/bin/env python3
"""Tests of the chaos proxy (tools/net/chaos_proxy.py): its seeded fates,
outages, capped lines and addresses without sockets, then the proxy itself
between a UDP echo server and a client on 127.0.0.1 and ::1.

    python3 tools/net/test_chaos_proxy.py
"""

import json
import os
import random
import socket
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chaos_proxy as cp  # noqa: E402


def _has_ipv6():
    try:
        s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        s.bind(("::1", 0))
        s.close()
        return True
    except OSError:
        return False


class Fates(unittest.TestCase):
    def _direction(self, seed="1", **kw):
        return cp.Direction(cp.Conditions(**kw), random.Random(seed))

    def test_clean(self):
        d = self._direction()
        for i in range(100):
            self.assertEqual(d.plan(i / 100.0, 50, False), [0])
        self.assertEqual(d.counts["packets"], 100)
        self.assertEqual(d.counts["bytes"], 5000)

    def test_rates(self):
        d = self._direction(loss=0.2, delay_ms=40, jitter_ms=30, dup=0.05, reorder=0.1)
        n = 20000
        delays = []
        for i in range(n):
            delays.extend(d.plan(i * 0.001, 100, False))
        c = d.counts
        self.assertAlmostEqual(c["lost"] / n, 0.2, delta=0.015)
        self.assertAlmostEqual(c["duplicated"] / (n - c["lost"]), 0.05, delta=0.01)
        self.assertAlmostEqual(c["reordered"] / (n - c["lost"]), 0.1, delta=0.015)
        self.assertEqual(len(delays), n - c["lost"] + c["duplicated"])
        self.assertGreaterEqual(min(delays), 40)
        self.assertLessEqual(max(delays), 40 + 30 + 1 + 40 + 30 + 20)
        plain = [x for x in delays if x <= 70]
        self.assertGreater(len(plain), 0.8 * len(delays))

    def test_seeded(self):
        a = self._direction("7", loss=0.3, jitter_ms=20, dup=0.1, reorder=0.1)
        b = self._direction("7", loss=0.3, jitter_ms=20, dup=0.1, reorder=0.1)
        c = self._direction("8", loss=0.3, jitter_ms=20, dup=0.1, reorder=0.1)
        fa = [a.plan(0, 1, False) for _ in range(500)]
        self.assertEqual(fa, [b.plan(5, 1, False) for _ in range(500)], "the same seed, the same fates")
        self.assertNotEqual(fa, [c.plan(0, 1, False) for _ in range(500)])

    def test_outage_keeps_the_stream(self):
        # an outage drops what it covers; later datagrams meet the fates they would have met
        a = self._direction("3", loss=0.5)
        b = self._direction("3", loss=0.5)
        fa = [a.plan(0, 1, i < 10) for i in range(100)]
        fb = [b.plan(0, 1, False) for i in range(100)]
        self.assertEqual(fa[:10], [[]] * 10)
        self.assertEqual(fa[10:], fb[10:])
        self.assertEqual(a.counts["outage"], 10)

    def test_outages(self):
        o = cp.Outages([(5.0, 5.5)], every_s=20, every_ms=500)
        self.assertFalse(o.down(4.99))
        self.assertTrue(o.down(5.0))
        self.assertTrue(o.down(5.4))
        self.assertFalse(o.down(5.5))
        self.assertFalse(o.down(0.1), "the first periodic outage comes after a period")
        self.assertTrue(o.down(20.2))
        self.assertFalse(o.down(20.6))
        self.assertTrue(o.down(40.0))

    def test_peak(self):
        d = self._direction()
        for i in range(30):
            d.plan(1.0 + i / 30.0, 10, False)
        d.plan(2.5, 10, False)
        self.assertEqual(d.to_json()["peak_bytes_per_s"], 300)

    def test_conditions_from_a_dictionary(self):
        c = cp.Conditions(loss=0.1, delay_ms=20)
        cp.apply_conditions(c, {"delay": 125, "jitter": 10, "up_loss": 5, "dup": 2}, "up_")
        self.assertEqual((c.delay_ms, c.jitter_ms), (125, 10))
        self.assertAlmostEqual(c.loss, 0.05)
        self.assertAlmostEqual(c.dup, 0.02)
        d = cp.Conditions(loss=0.1)
        cp.apply_conditions(d, {"up_loss": 5, "down_delay": 7}, "down_")
        self.assertAlmostEqual(d.loss, 0.1, msg="another way's key leaves it")
        self.assertEqual(d.delay_ms, 7)

    def test_endpoints(self):
        self.assertEqual(cp.parse_endpoint("127.0.0.1:42100")[1], ("127.0.0.1", 42100))
        if _has_ipv6():
            fam, addr = cp.parse_endpoint("[::1]:42100")
            self.assertEqual((fam, addr[0], addr[1]), (socket.AF_INET6, "::1", 42100))
        for bad in ("::1:42100", "127.0.0.1", "[::1]42100", "127.0.0.1:70000", "127.0.0.1:x"):
            with self.assertRaises(ValueError):
                cp.parse_endpoint(bad)


class Links(unittest.TestCase):
    """The capped line (the host's uplink or downlink): a token bucket behind
    a queue of so many milliseconds, tail drop when it is full."""

    def test_idle_line_passes_at_once(self):
        link = cp.Link(1000, queue_ms=100, overhead=28, burst=1500)
        self.assertEqual(link.offer(0.0, 100), 0.0)
        self.assertEqual(link.offer(0.5, 1000), 0.0, "the bucket filled again meanwhile")
        # below the rate nothing waits: 128 B every 10 ms is 102 kbit/s of 1000
        self.assertEqual([link.offer(1.0 + i * 0.01, 100) for i in range(100)], [0.0] * 100)
        self.assertEqual(link.counts["dropped"], 0)

    def test_rate_and_tail_drop(self):
        # 400 kbit/s is 50 000 B/s; 1000 B every 10 ms (100 000 B/s) for 10 s: half passes
        link = cp.Link(400, queue_ms=200, overhead=0, burst=0)
        waits = [link.offer(i * 0.01, 1000) for i in range(1000)]
        passed = [w for w in waits if w is not None]
        c = link.counts
        self.assertAlmostEqual(c["passed_bytes"] / 10.0, 50000, delta=2500, msg="the line's rate")
        self.assertAlmostEqual(c["dropped"] / 1000.0, 0.5, delta=0.03)
        self.assertEqual(c["passed"] + c["dropped"], 1000)
        self.assertLessEqual(max(passed), 0.2 + 0.02 + 1e-9, "the queue's 200 ms and the datagram's own 20 ms at most")
        self.assertGreater(max(passed), 0.18, "the queue filled")
        j = link.to_json()
        self.assertAlmostEqual(j["dropped_pct"], 50, delta=3)
        self.assertGreater(j["wait_mean_ms"], 150, "full most of the time")
        self.assertGreaterEqual(j["seconds_half_full"], 9)

    def test_first_in_first_out(self):
        link = cp.Link(100, queue_ms=1000, overhead=28, burst=0)
        leave = []
        for i in range(20):
            t = i * 0.001
            leave.append(t + link.offer(t, 100))
        self.assertEqual(leave, sorted(leave))
        # back to back: each takes (100 + 28) * 8 / 100 000 s, the headers counted
        self.assertAlmostEqual(leave[-1] - leave[0], 19 * 128 * 8 / 100000.0, places=6)

    def test_queue_of_milliseconds(self):
        # a burst of 100 datagrams at once: the queue holds 50 ms of a 1 Mbit/s line (6 250 B)
        link = cp.Link(1000, queue_ms=50, overhead=0, burst=0)
        waits = [link.offer(1.0, 250) for _ in range(100)]
        self.assertEqual(sum(1 for w in waits if w is not None), 26, "50 ms of line, and the one on it")
        self.assertEqual(waits[30:], [None] * 70, "tail drop: the late ones go")


def proxy_ports(rep):
    return [int(x.rsplit(":", 1)[1]) for x in rep["listen"]]


class Echo(threading.Thread):
    """A UDP server sending every datagram back."""

    def __init__(self, host):
        super().__init__(daemon=True)
        fam = socket.AF_INET6 if ":" in host else socket.AF_INET
        self.sock = socket.socket(fam, socket.SOCK_DGRAM)
        self.sock.bind((host, 0))
        self.sock.settimeout(0.1)
        self.port = self.sock.getsockname()[1]
        self.peers = set()
        self.running = True

    def run(self):
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            self.peers.add(addr)
            self.sock.sendto(data, addr)


class Sockets(unittest.TestCase):
    def _run(self, host, up, down, outages=None, packets=200, gap=0.002, clients=1, spread=False, clean_for=0.0,
             links=None, size=40):
        echo = Echo(host)
        echo.start()
        fam = socket.AF_INET6 if ":" in host else socket.AF_INET
        name = "[%s]" % host if ":" in host else host
        report = os.path.join(tempfile.mkdtemp(), "proxy.json")
        proxy = cp.Proxy([cp.parse_endpoint("%s:0" % name) for _ in range(2)],
                         cp.parse_endpoint("%s:%d" % (name, echo.port)), up, down, outages, seed="t", report=report,
                         spread=spread, clean_for=clean_for, links=links)
        th = threading.Thread(target=proxy.run, daemon=True)
        th.start()
        socks = []
        for _ in range(clients):
            s = socket.socket(fam, socket.SOCK_DGRAM)
            s.settimeout(0.05)
            socks.append(s)
        sent_at = {}
        got = {}
        lock = threading.Lock()
        receiving = [True]

        def receive(k, s):
            # concurrently, so neither the timing nor a full socket buffer skews it
            while receiving[0]:
                try:
                    data = s.recv(65535)
                except socket.timeout:
                    continue
                except OSError:
                    return
                now = time.monotonic()
                kk, i, _ = data.split(b"/", 2)
                key = (int(kk), int(i))
                with lock:
                    got.setdefault(key, []).append(now - sent_at[key])

        t0 = time.monotonic()
        threads = [threading.Thread(target=receive, args=(k, s), daemon=True) for k, s in enumerate(socks)]
        for th_ in threads:
            th_.start()
        for i in range(packets):
            for k, s in enumerate(socks):
                payload = b"%d/%d/" % (k, i) + b"x" * size
                with lock:
                    sent_at[(k, i)] = time.monotonic()
                s.sendto(payload, (host, proxy.ports[k % 2]))     # the clients by turns to each port
            time.sleep(gap)
        time.sleep(1.0)
        receiving[0] = False
        for th_ in threads:
            th_.join(1)
        proxy.stop()
        th.join(5)
        echo.running = False
        echo.join(1)
        for s in socks:
            s.close()
        with open(report) as f:
            rep = json.load(f)
        return got, rep, echo, time.monotonic() - t0

    def _clean_and_delayed(self, host):
        got, rep, echo, _ = self._run(host, cp.Conditions(delay_ms=30), cp.Conditions(delay_ms=10), clients=2)
        self.assertEqual(len(got), 400, "every datagram came back")
        rtts = [min(v) for v in got.values()]
        self.assertGreaterEqual(min(rtts), 0.038, "30 ms up and 10 ms down")
        self.assertLess(sorted(rtts)[len(rtts) // 2], 0.1)
        self.assertEqual(len(echo.peers), 2, "a session (an upstream socket) per client")
        self.assertEqual(len(rep["sessions"]), 2)
        self.assertEqual(sorted(s["via"] for s in rep["sessions"]), sorted(proxy_ports(rep)),
                         "each session filed by the port it came to")
        for s in rep["sessions"]:
            for way in ("up", "down"):
                self.assertEqual(s[way]["packets"], 200)
                self.assertEqual(s[way]["forwarded"], 200)
                self.assertEqual(s[way]["forwarded_bytes"], s[way]["bytes"])
        self.assertEqual(rep["totals"]["up"]["packets"], 400)
        self.assertEqual(rep["conditions"]["up"]["delay_ms"], 30)

    def test_ipv4(self):
        self._clean_and_delayed("127.0.0.1")

    @unittest.skipUnless(_has_ipv6(), "no IPv6 loopback")
    def test_ipv6(self):
        self._clean_and_delayed("::1")

    def test_clean_at_first(self):
        # everything passes for the first 0.3 s, then half is lost
        got, rep, _, _ = self._run("127.0.0.1", cp.Conditions(loss=0.5), cp.Conditions(), packets=100, gap=0.006,
                                   clean_for=0.3)
        up = rep["sessions"][0]["up"]
        early = [k for k in got if k[1] < 40]
        self.assertEqual(len(early), 40, "the first 0.24 s clean")
        self.assertGreater(up["lost"], 10, "lossy after")

    def test_control_file_changes_the_delay_while_it_runs(self):
        # 20 ms each way at first; the control file then asks for 100 ms up
        echo = Echo("127.0.0.1")
        echo.start()
        control = os.path.join(tempfile.mkdtemp(), "control.json")
        proxy = cp.Proxy(cp.parse_endpoint("127.0.0.1:0"), cp.parse_endpoint("127.0.0.1:%d" % echo.port),
                         cp.Conditions(delay_ms=20), cp.Conditions(delay_ms=20), control=control)
        th = threading.Thread(target=proxy.run, daemon=True)
        th.start()
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(2.0)

        def rtt():
            t = time.monotonic()
            s.sendto(b"x", ("127.0.0.1", proxy.port))
            s.recv(100)
            return time.monotonic() - t

        try:
            before = min(rtt() for _ in range(3))
            with open(control, "w") as f:
                json.dump({"up_delay": 100}, f)
            time.sleep(0.6)
            after = min(rtt() for _ in range(3))
        finally:
            proxy.stop()
            th.join(5)
            echo.running = False
            echo.join(1)
            s.close()
        self.assertGreaterEqual(before, 0.039)
        self.assertLess(before, 0.1)
        self.assertGreaterEqual(after, 0.119, "100 ms up and 20 down")
        self.assertEqual(proxy.down.delay_ms, 20)

    def test_spread_sources(self):
        _, rep, echo, _ = self._run("127.0.0.1", cp.Conditions(), cp.Conditions(), packets=20, clients=2,
                                    spread=True)
        self.assertEqual(sorted(a[0] for a in echo.peers), ["127.0.0.2", "127.0.0.3"],
                         "each listening port's clients from an address of their own")

    def test_loss_dup_and_outage(self):
        got, rep, _, _ = self._run("127.0.0.1", cp.Conditions(loss=0.3), cp.Conditions(dup=0.5), packets=400)
        up = rep["sessions"][0]["up"]
        down = rep["sessions"][0]["down"]
        self.assertAlmostEqual(up["lost"] / 400, 0.3, delta=0.08)
        self.assertEqual(down["packets"], 400 - up["lost"])
        self.assertEqual(down["forwarded"], down["packets"] + down["duplicated"])
        self.assertEqual(len(got), 400 - up["lost"])
        self.assertEqual(sum(len(v) for v in got.values()), down["forwarded"])
        # an outage from 0.2 s for 0.3 s: nothing sent then comes back
        got, rep, _, _ = self._run("127.0.0.1", cp.Conditions(), cp.Conditions(),
                                   cp.Outages([(0.2, 0.5)]), packets=100, gap=0.008)
        up = rep["sessions"][0]["up"]
        self.assertGreater(up["outage"], 20)
        self.assertEqual(len(got), 100 - up["outage"])

    def test_capped_uplink_shared(self):
        # the host's uplink (down) capped at 400 kbit/s - 50 000 B/s, 100 datagrams of 500 B on the
        # line - with a 100 ms queue; two clients' echoes together offer 400 a second for a second
        link = cp.Link(400, queue_ms=100, overhead=28, burst=1500)
        got, rep, _, took = self._run("127.0.0.1", cp.Conditions(), cp.Conditions(delay_ms=20), packets=200, gap=0.005,
                                      clients=2, links={"down": link}, size=464)
        line = rep["links"]["down"]
        self.assertEqual(line["rate_kbit"], 400)
        self.assertEqual(line["passed"] + line["dropped"], 400, "every echo offered to the one line")
        self.assertEqual(sum(s["down"]["queue_full"] for s in rep["sessions"]), line["dropped"],
                         "the sessions' drops are the line's")
        self.assertEqual(len(got), line["passed"], "what passed the line came back")
        sending = 200 * 0.005
        self.assertLess(line["passed"], 50000 * (sending + 0.25) / 500, "no more than the line's rate")
        self.assertGreater(line["passed"], 50000 * sending / 500 * 0.6)
        for k in (0, 1):
            # (not evenly: a tail drop takes whoever comes last to a full queue, here client 1, which
            # sends right after client 0 each time - as the host's datagrams go in the same order each tick)
            self.assertGreater(sum(1 for key in got if key[0] == k), 0, "one line for both clients")
        rtts = sorted(min(v) for v in got.values())
        self.assertGreater(rtts[-1], 0.02 + 0.07, "the queue filled: its wait on top of the delay")
        self.assertLess(rtts[-1], 0.02 + 0.1 + 0.08, "never more than the queue (and the scheduling's slack)")
        self.assertNotIn("up", rep["links"])

    def test_capped_downlink(self):
        # the host's downlink (up): the clients' datagrams through the network, then the line
        link = cp.Link(200, queue_ms=50, overhead=28, burst=0)
        got, rep, _, _ = self._run("127.0.0.1", cp.Conditions(delay_ms=10), cp.Conditions(), packets=100, gap=0.004,
                                   links={"up": link}, size=464)
        line = rep["links"]["up"]
        self.assertEqual(line["passed"] + line["dropped"], 100)
        self.assertGreater(line["dropped"], 30, "250 a second offered to a line of 50")
        self.assertEqual(rep["sessions"][0]["up"]["queue_full"], line["dropped"])
        self.assertEqual(len(got), line["passed"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
