#!/usr/bin/env python3
"""The online soak's report (tools/bin/net-soak): one run's folder - each
machine's log with its "SOAK {json}" line (game/test/net/online_match.gd),
the chaos proxy's proxy.json, the hash comparison's compare.log - read into a
table and summary.json.

    soak_report.py RUN_DIR

Per machine: its result, ticks run, hashes made and checked on the way,
mismatches, the longest stall and the stalls over 250 ms and 1 s, the round
trip, how long joining took, the connections lost in mid-match and joined
again (and the seconds away until the snapshot), the bandwidth, the CPU and
the memory. A client restarted after its process was killed is marked *, a
Windows client (under wine) w. The bandwidth of a
client: up (what it sent) and down (what reached it), each as the messages
themselves ("payload"), ENet's datagrams before encryption ("enet") and the
DTLS records on the wire (the proxy's count; IP and UDP headers - 28 bytes a
datagram over IPv4, 48 over IPv6 - come on top), in bytes a second of its
match (a restarted client: the time the proxy saw it). The host's upload is
every client's down together, its busiest second too; the achieved rate is
the host's ticks a second. A client's buffer: the ticks it held beyond the
one it ran and how far the host's game was ahead (ms), the round trip, the
share of the host's ticks that came as STREAM messages and its resend
requests; ENet's packet throttle (mean, lowest); the host's pace (MwNetPace:
how often and how long it sent a machine its stream every second tick, the
longest queue it saw); with a capped line (net-soak
--uplink) what it passed and dropped and how long datagrams waited in its
queue. Exit status 1 if anything failed (a machine's
result, a desync, the comparison); a run cut by its time limit is reported
as far as it went ("part").
"""

import json
import os
import re
import sys


def soak_line(path):
    """The SOAK json and the RESULT line of a machine's log ({} and "" if none)."""
    soak, result = {}, ""
    if not os.path.exists(path):
        return soak, result
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith("SOAK "):
                soak = json.loads(line[5:])
            m = re.search(r"RESULT (\S+)", line)
            if m and not line.startswith("compare"):
                result = m.group(1).strip()
    return soak, result


def rate(nbytes, seconds):
    return nbytes / seconds if seconds > 0 else 0.0


def kb(v):
    return "%.1f" % (v / 1024.0)


def main(run):
    with open(os.path.join(run, "soak.json")) as f:
        conf = json.load(f)
    proxy = {}
    p = os.path.join(run, "proxy.json")
    if os.path.exists(p):
        with open(p) as f:
            proxy = json.load(f)
    base = int(conf["port"])
    ip_header = 48 if conf.get("ip") == "6" else 28
    rows = []
    ok = True
    # each client's proxy sessions, by the port it came to
    by_client = {}
    for s in proxy.get("sessions", []):
        by_client.setdefault(int(s["via"]) - base, []).append(s)
    machines = [("host", "host.log")] + [("client%d" % k, "client%d.log" % k) for k in range(1, conf["clients"] + 1)]
    summary = {"conf": conf, "machines": {}, "proxy_totals": proxy.get("totals", {})}
    for name, log in machines:
        soak, result = soak_line(os.path.join(run, log))
        rejoined = False
        if name != "host" and os.path.exists(os.path.join(run, name + "-rejoin.log")):
            soak, result = soak_line(os.path.join(run, name + "-rejoin.log"))
            rejoined = True
        win = name != "host" and (conf.get("windows") == "all" or name[6:] in str(conf.get("windows", "")).split(","))
        row = {"name": name + ("*" if rejoined else "") + (" w" if win else ""), "result": result or "no result",
               "soak": soak}
        if result != "ok":
            ok = False
        if name != "host":
            k = int(name[6:])
            sessions = by_client.get(k, [])
            up = sum(s["up"]["bytes"] for s in sessions)
            up_n = sum(s["up"]["packets"] for s in sessions)
            down = sum(s["down"]["forwarded_bytes"] for s in sessions)
            down_n = sum(s["down"]["forwarded"] for s in sessions)
            firsts = [s[w]["first_s"] for s in sessions for w in ("up", "down") if s[w]["first_s"] is not None]
            lasts = [s[w]["last_s"] for s in sessions for w in ("up", "down") if s[w]["last_s"] is not None]
            span = (max(lasts) - min(firsts)) if firsts else 0.0
            row["wire"] = {"up": up, "up_datagrams": up_n, "down": down, "down_datagrams": down_n, "span_s": span,
                           "sessions": len(sessions)}
        rows.append(row)
        summary["machines"][name] = row
    # the comparison
    compare = ""
    cp = os.path.join(run, "compare.log")
    if os.path.exists(cp):
        with open(cp, errors="replace") as f:
            for line in f:
                if line.startswith("compare") or "RESULT" in line:
                    compare = line.strip()
    if "RESULT ok" not in compare:
        ok = False
    compared = 0
    if os.path.exists(cp):
        with open(cp, errors="replace") as f:
            m = re.search(r"(\d+) clients, (\d+) hashes compared, all equal", f.read())
            if m:
                compared = int(m.group(2))
    summary["compared"] = compared
    summary["compare"] = compare

    c = conf
    if c.get("windows"):
        print("(clients marked w: Windows' Godot under wine)")
    print("soak %s: %d client(s) over IPv%s to %s, loss %s %%, delay %s ms, jitter %s ms, dup %s %%, "
          "reorder %s %%, outages %s, rate %s, clock %s s%s%s%s%s" % (
              c["name"], c["clients"], c["ip"], c["address"], c["loss"], c["delay"], c["jitter"], c["dup"],
              c["reorder"], c["outage_every"] or "none", c["rate"], c["clock"],
              ", clean for the first %s s" % c["clean_for"] if float(c.get("clean_for", 0)) > 0 else "",
              ", client %s killed and restarted" % c["kill"] if c.get("kill") else "",
              ", the host's uplink %s kbit/s" % c["uplink_kbit"] if float(c.get("uplink_kbit", 0)) > 0 else "",
              (", queue %s ms" % c["queue_ms"] if float(c.get("uplink_kbit", 0)) > 0
               or float(c.get("downlink_kbit", 0)) > 0 else "")
              + (", throttle %s" % c["throttle"] if c.get("throttle", "game") != "game" else "")))
    head = ("%-9s %-6s %6s %6s %6s %4s %7s %5s %4s %5s %6s %5s | %18s | %18s | %5s %5s"
            % ("machine", "result", "ticks", "hashes", "checkd", "mism", "stall", ">250", ">1s", "rtt", "join",
               "drops", "up KB/s pay/enet/wire", "down KB/s pay/enet/wire", "cpu%", "MB"))
    print(head)
    tot_payload_down = 0
    tot_enet_down = 0
    tot_wire_down = 0
    tot_wire_dgrams = 0
    tot_enet_dgrams = 0
    for r in rows:
        s = r["soak"]
        t = s.get("traffic", {})
        res = "ok" if r["result"] == "ok" else ("part" if s.get("partial") else "FAIL")
        cpu = 100.0 * s.get("cpu_s", 0) / s["wall_s"] if s.get("wall_s") else 0
        line = "%-9s %-6s %6s %6s %6s %4s %6sms %5s %4s %5s %6s %5s" % (
            r["name"], res, s.get("ticks", "-"), s.get("hashes", "-"), s.get("checked", "-"),
            s.get("mismatches", "-"), s.get("stall_max_ms", "-"), s.get("stalls_over_250ms", "-"),
            s.get("stalls_over_1s", "-"), s.get("rtt_ms", "-"), s.get("join_ms", "-"),
            ("%d/%ds" % (s["drops"], s.get("away_ms", 0) // 1000)) if s.get("drops") else "-")
        if "wire" in r and s:
            w = r["wire"]
            # over its match (lobby traffic is small); a restarted client's
            # sessions span both its processes: the proxy's span
            secs = w["span_s"] if "*" in r["name"] else s.get("match_s", 0)
            up = "%5s/%5s/%5s" % (kb(rate(t.get("sent", 0), secs)), kb(rate(t.get("enet_sent", 0), secs)),
                                   kb(rate(w["up"], secs)))
            down = "%5s/%5s/%5s" % (kb(rate(t.get("received", 0), secs)), kb(rate(t.get("enet_received", 0), secs)),
                                     kb(rate(w["down"], secs)))
            if "*" not in r["name"]:                 # a restarted client's first process left no counts
                tot_payload_down += t.get("received", 0)
                tot_enet_down += t.get("enet_received", 0)
                tot_wire_down += w["down"]
                tot_wire_dgrams += w["down_datagrams"]
                tot_enet_dgrams += t.get("enet_received_datagrams", 0)
            r["rates"] = {"up_payload": rate(t.get("sent", 0), secs), "up_enet": rate(t.get("enet_sent", 0), secs),
                          "up_wire": rate(w["up"], secs), "down_payload": rate(t.get("received", 0), secs),
                          "down_enet": rate(t.get("enet_received", 0), secs), "down_wire": rate(w["down"], secs)}
        else:
            up = down = "%17s" % "-"
        print("%s | %18s | %18s | %5.0f %5.0f" % (line, up, down, cpu, s.get("rss_max_kb", 0) / 1024.0))
    host = rows[0]["soak"]
    tot = proxy.get("totals", {})
    if host and tot:
        span = host.get("match_s", 0)
        ht = host.get("traffic", {})
        busiest = tot["down"].get("busiest_seconds", [])
        print("host upload: %s KB/s payload, %s KB/s ENet, %s KB/s on the wire (+%d B IP/UDP a datagram), "
              "busiest second %s KB%s" % (kb(rate(ht.get("sent", 0), span)), kb(rate(ht.get("enet_sent", 0), span)),
                                          kb(rate(tot["down"]["bytes"], span)), ip_header,
                                          kb(tot["down"].get("peak_bytes_per_s", 0)),
                                          " (at %s s)" % ", ".join(str(b[0]) for b in busiest[:3]) if busiest else ""))
        summary["host_upload"] = {"payload": rate(ht.get("sent", 0), span), "enet": rate(ht.get("enet_sent", 0), span),
                                  "wire": rate(tot["down"]["bytes"], span),
                                  "peak_wire": tot["down"].get("peak_bytes_per_s", 0)}
        print("proxy: up %d datagrams (%d lost, %d in outages, %d doubled), down %d (%d lost, %d in outages, "
              "%d doubled); its CPU %.1f s" % (tot["up"]["packets"], tot["up"]["lost"], tot["up"]["outage"],
                                               tot["up"]["duplicated"], tot["down"]["packets"], tot["down"]["lost"],
                                               tot["down"]["outage"], tot["down"]["duplicated"],
                                               proxy.get("cpu_s", 0)))
    if tot_enet_down and tot_wire_dgrams:
        per = (tot_wire_down - tot_enet_down) / max(1, tot_wire_dgrams)
        print("DTLS: %d B on the wire for %d B of ENet datagrams (+%.1f %%, %.1f B a datagram); ENet: %d B for %d B "
              "of messages (+%.1f %%)" % (tot_wire_down, tot_enet_down, 100.0 * (tot_wire_down - tot_enet_down)
                                          / tot_enet_down, per, tot_enet_down, tot_payload_down,
                                          100.0 * (tot_enet_down - tot_payload_down) / max(1, tot_payload_down)))
        summary["dtls"] = {"wire": tot_wire_down, "enet": tot_enet_down, "payload": tot_payload_down,
                           "per_datagram": per, "wire_datagrams": tot_wire_dgrams, "enet_datagrams": tot_enet_dgrams}
    if host.get("match_s"):
        cpu = sum(r["soak"].get("cpu_s", 0) for r in rows if r["soak"])
        print("rate: the host ran %.1f ticks a second (asked: %s); CPU: the machines' %.0f s in %.0f s (%.1f of %d "
              "cores)" % (host["ticks"] / host["match_s"], c["rate"], cpu, host.get("wall_s", 0),
                          cpu / max(1.0, host.get("wall_s", 0)), c.get("nproc", 0)))
        summary["achieved_rate"] = host["ticks"] / host["match_s"]
    # the clients' buffers and streams
    buffers = {}
    for r in rows[1:]:
        s = r["soak"]
        b = s.get("buffer")
        if not b:
            continue
        st = s.get("stream", {})
        share = 100.0 * st.get("packets", 0) / max(1, s.get("ticks", 0))
        buffers[r["name"]] = dict(b, stream_share=share, requests=st.get("requests", 0), held=s.get("held", 0))
    if buffers:
        print("buffers: %s" % "; ".join(
            "%s held %.1f (max %d) ticks, the host %d ms ahead (95 %%: %d, max %d), rtt %d (max %d) ms, STREAM %.0f %% "
            "of ticks, %d resend requests, %d frames held" % (
                n, b["lead_mean"], b["lead_max"], b["host_lead_mean_ms"], b["host_lead_p95_ms"], b["host_lead_max_ms"],
                b["rtt_mean_ms"], b["rtt_max_ms"], b["stream_share"], b["requests"], b["held"])
            for n, b in buffers.items()))
        summary["buffers"] = buffers
        vals = list(buffers.values())
        summary["buffer_worst"] = {"host_lead_mean_ms": max(b["host_lead_mean_ms"] for b in vals),
                                   "host_lead_p95_ms": max(b["host_lead_p95_ms"] for b in vals),
                                   "host_lead_max_ms": max(b["host_lead_max_ms"] for b in vals),
                                   "stream_share_min": min(b["stream_share"] for b in vals),
                                   "requests": sum(b["requests"] for b in vals)}
    ht = host.get("traffic", {}) if host else {}
    if ht.get("throttle_samples"):
        mean = ht["throttle_sum"] / ht["throttle_samples"]
        print("ENet's throttle (the host's peers, of 32): mean %.1f, lowest %d; %s (the host's reliable messages: "
              "%d, %.1f KB)" % (mean, ht.get("throttle_low", 32), ",".join(str(x) for x in host.get("throttle", [])),
                                ht.get("sent_reliable_messages", 0), ht.get("sent_reliable", 0) / 1024.0))
        summary["throttle"] = {"mean": mean, "low": ht.get("throttle_low", 32), "setting": host.get("throttle")}
    paces = host.get("paces", {}) if host else {}
    if paces:
        print("the host's pace (a STREAM every second tick while a line is full): %s" % "; ".join(
            "machine %s slowed %d times, %.1f s so, longest queue %d ms" % (m, p["slowed"], p["slow_ms"] / 1000.0,
                                                                         p["queue_max_ms"])
            for m, p in sorted(paces.items())))
        summary["paces"] = paces
    for way, link in proxy.get("links", {}).items():
        print("the host's %s capped at %s kbit/s, queue %s ms: %d datagrams passed, %d dropped (%.1f %%) with the "
              "queue full; waited %.0f ms on average, %.0f at most; %d of %d seconds over half full" % (
                  "uplink" if way == "down" else "downlink", link["rate_kbit"], link["queue_ms"], link["passed"],
                  link["dropped"], link["dropped_pct"], link["wait_mean_ms"], link["wait_max_ms"],
                  link["seconds_half_full"], link["seconds"]))
        summary["link_" + way] = link
    mism = sum(int(r["soak"].get("mismatches", 0)) for r in rows if r["soak"])
    print("desyncs: %d found on the way; %s" % (mism, compare or "no comparison"))
    if mism:
        ok = False
    summary["ok"] = ok
    with open(os.path.join(run, "summary.json"), "w") as f:
        json.dump(summary, f, indent=1)
    print("soak %s RESULT %s" % (c["name"], "ok" if ok else "failed"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
