pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: store

    readonly property string configPath: Quickshell.env("HOME") + "/.config/enigmaos/feeds"
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/enigmaos_feeds"
    readonly property string statePath: cacheDir + "/feeds.json"
    readonly property int maxPosts: 30
    readonly property var units: ({ m: 60000, h: 3600000, d: 86400000, w: 604800000 })

    property date now: new Date()
    Timer { interval: 60000; running: true; repeat: true; onTriggered: store.now = new Date() }

    property var config: []
    property var feeds: []
    property real lastChecked: 0
    property real lastFetched: 0
    property bool configOpen: false
    property var _job: null
    property bool _refetch: false
    property bool _configLoaded: false
    property bool _stateLoaded: false
    readonly property bool fetching: _job !== null

    Timer {
        interval: 20 * 60000
        running: store._configLoaded && store._stateLoaded
        repeat: true
        triggeredOnStart: true
        onTriggered: store.refresh()
    }

    Timer { id: abortTimer; interval: 25000; onTriggered: if (store._job) store._finish(store._job) }

    Process { command: ["mkdir", "-p", store.cacheDir]; running: true }

    FileView {
        id: configFile
        path: store.configPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            store.config = store.parseConfig(text());
            store._configLoaded = true;
        }
        onLoadFailed: store._configLoaded = true
    }

    FileView {
        id: stateFile
        path: store.statePath
        printErrors: false
        onLoaded: store._adoptState(text())
        onLoadFailed: store._adoptState("")
    }

    function _adoptState(t) {
        let d = {};
        try { d = JSON.parse(t); } catch (e) {}
        store.feeds = d.feeds || [];
        store.lastChecked = d.lastChecked || Date.now() - store.units.d;
        store.lastFetched = d.fetched || 0;
        store._stateLoaded = true;
    }

    function _saveState() {
        if (store._stateLoaded)
            stateFile.setText(JSON.stringify({ lastChecked: store.lastChecked, fetched: store.lastFetched, feeds: store.feeds }, null, 1));
    }

    function parseDuration(v) {
        const m = /^(\d+)\s*([mhdw])$/.exec(String(v).trim().toLowerCase());
        return m ? parseInt(m[1]) * store.units[m[2]] : 0;
    }

    function duration(ms) {
        if (!ms) return "off";
        for (const u of ["w", "d", "h", "m"])
            if (ms % store.units[u] === 0)
                return ms / store.units[u] + u;
        return Math.round(ms / 60000) + "m";
    }

    function parseConfig(text) {
        const cats = [];
        let cat = null;
        for (let line of text.split("\n")) {
            line = line.trim();
            if (!line || line.startsWith("#"))
                continue;
            const sec = /^\[(.+)\]$/.exec(line);
            const set = /^(\w+)\s*=\s*(.*)$/.exec(line);
            if (sec || !cat) {
                cat = { name: sec ? sec[1].trim() : "general", counter: true, markRead: 0, clear: 0, feeds: [] };
                cats.push(cat);
                if (sec)
                    continue;
            }
            if (set) {
                const k = set[1].toLowerCase(), v = set[2].trim().toLowerCase();
                if (k === "counter") cat.counter = ["on", "yes", "true", "1"].includes(v);
                else if (k === "mark_read") cat.markRead = store.parseDuration(v);
                else if (k === "clear") cat.clear = store.parseDuration(v);
                continue;
            }
            const m = /^(\S+)\s*(.*)$/.exec(line);
            cat.feeds.push({ url: m[1], name: m[2].trim() });
        }
        return cats;
    }

    function editableConfig() {
        return store.config.map(c => ({
            name: c.name, counter: c.counter,
            markRead: store.duration(c.markRead), clear: store.duration(c.clear),
            feeds: c.feeds.map(f => ({ url: f.url, name: f.name }))
        }));
    }

    function writeConfig(cats) {
        const out = ["# [category]  counter = on|off  mark_read = 12h|2d|1w|off  clear = 30d|off", "# url [display name]"];
        for (const c of cats) {
            out.push("",
                "[" + (String(c.name).replace(/[\[\]]/g, "").trim() || "general") + "]",
                "counter = " + (c.counter ? "on" : "off"),
                "mark_read = " + (String(c.markRead).trim() || "off"),
                "clear = " + (String(c.clear).trim() || "off"));
            for (const f of c.feeds) {
                const url = String(f.url).replace(/\s+/g, "");
                if (url)
                    out.push(url + (String(f.name).trim() ? " " + String(f.name).trim() : ""));
            }
        }
        const text = out.join("\n") + "\n";
        store.config = store.parseConfig(text);
        configFile.setText(text);
    }

    function setCounter(name, on) {
        store.writeConfig(store.editableConfig().map(c => c.name === name ? Object.assign(c, { counter: on }) : c));
    }

    function markSeen() {
        store.lastChecked = Date.now();
        store.now = new Date();
        store._saveState();
    }

    function refresh() {
        if (store._job) {
            store._refetch = true;
            return;
        }
        const defs = [];
        for (const c of store.config)
            for (const f of c.feeds)
                defs.push(f);
        const prev = {};
        for (const f of store.feeds)
            prev[f.url] = f;
        const job = { defs: defs, prev: prev, results: {}, left: defs.length, xhrs: [] };
        store._job = job;
        if (defs.length === 0) {
            store._finish(job);
            return;
        }
        abortTimer.restart();
        for (const def of defs)
            store._fetch(job, def);
    }

    function _fetch(job, def) {
        const prev = job.prev[def.url];
        const xhr = new XMLHttpRequest();
        job.xhrs.push(xhr);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || store._job !== job || def.url in job.results)
                return;
            job.results[def.url] = store._merge(def, prev, xhr);
            if (--job.left === 0)
                store._finish(job);
        };
        xhr.open("GET", def.url);
        xhr.setRequestHeader("User-Agent", "enigmaOS-feeds/1.0");
        if (prev && prev.etag)
            xhr.setRequestHeader("If-None-Match", prev.etag);
        if (prev && prev.modified)
            xhr.setRequestHeader("If-Modified-Since", prev.modified);
        xhr.send();
    }

    function _finish(job) {
        abortTimer.stop();
        store._job = null;
        for (const x of job.xhrs)
            if (x.readyState !== XMLHttpRequest.DONE)
                x.abort();
        store.feeds = job.defs.map(def => job.results[def.url]
            || Object.assign({ url: def.url, title: def.url, posts: [] }, job.prev[def.url] || {}, { error: "timeout" }));
        store.lastFetched = Date.now();
        store.now = new Date();
        store._saveState();
        if (store._refetch) {
            store._refetch = false;
            store.refresh();
        }
    }

    function _merge(def, prev, xhr) {
        const out = {
            url: def.url,
            title: (prev && prev.title) || def.url,
            etag: (prev && prev.etag) || "",
            modified: (prev && prev.modified) || "",
            error: "",
            posts: (prev && prev.posts) || []
        };
        if (xhr.status === 304)
            return out;
        if (xhr.status !== 200) {
            out.error = xhr.status ? "HTTP " + xhr.status : "unreachable";
            return out;
        }
        const parsed = store.parseFeed(xhr.responseText, def.url);
        if (!parsed) {
            out.error = "not a feed";
            return out;
        }
        const fetched = Date.now();
        const known = {};
        for (const p of out.posts)
            known[p.id] = p.seen;
        const firstFetch = out.posts.length === 0;
        for (const p of parsed.posts) {
            p.seen = p.id in known ? known[p.id] : (firstFetch ? Math.min(p.time || 0, fetched) : fetched);
            p.time = Math.min(p.time || p.seen, fetched);
        }
        parsed.posts.sort((a, b) => b.time - a.time);
        out.title = parsed.title || out.title;
        out.etag = xhr.getResponseHeader("ETag") || "";
        out.modified = xhr.getResponseHeader("Last-Modified") || "";
        out.posts = parsed.posts.slice(0, store.maxPosts);
        return out;
    }

    function parseFeed(text, base) {
        if (!/<(rss|feed|rdf:RDF)[\s>]/.test(text))
            return null;
        const tag = /<entry[\s>]/.test(text) ? "entry" : "item";
        const head = text.split(new RegExp("<" + tag + "[\\s>]"))[0];
        const blocks = text.match(new RegExp("<" + tag + "[\\s>][\\s\\S]*?</" + tag + ">", "g")) || [];
        const posts = [];
        for (const b of blocks) {
            let link = "";
            if (tag === "entry") {
                for (const l of b.match(/<link\b[^>]*>/g) || []) {
                    const rel = /\brel=["']([^"']+)/.exec(l), href = /\bhref=["']([^"']+)/.exec(l);
                    if (href && (!rel || rel[1] === "alternate")) {
                        link = store._decode(href[1]);
                        break;
                    }
                }
            } else {
                link = store._tag(b, "link");
            }
            const id = store._tag(b, tag === "entry" ? "id" : "guid") || link || store._tag(b, "title");
            if (!id)
                continue;
            posts.push({
                id: id,
                title: store._clean(store._tag(b, "title")) || "(untitled)",
                url: link ? store._resolve(base, link.trim()) : base,
                time: store._date(store._tag(b, "published") || store._tag(b, "updated") || store._tag(b, "pubDate") || store._tag(b, "dc:date"))
            });
        }
        return { title: store._clean(store._tag(head, "title")), posts: posts };
    }

    function _tag(s, name) {
        const m = new RegExp("<" + name + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + name + ">").exec(s);
        if (!m)
            return "";
        const cdata = /^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/.exec(m[1]);
        return cdata ? cdata[1] : store._decode(m[1]);
    }

    function _decode(s) {
        const named = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };
        return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, e) => {
            if (e[0] === "#")
                return String.fromCodePoint(e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
            return named[e.toLowerCase()] !== undefined ? named[e.toLowerCase()] : all;
        });
    }

    function _clean(s) {
        return store._decode(String(s).replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim();
    }

    function _resolve(base, link) {
        if (/^[a-z][a-z0-9+.-]*:/i.test(link))
            return link;
        const origin = /^([a-z]+:\/\/[^\/]+)/i.exec(base);
        if (link.startsWith("//"))
            return base.split(":")[0] + ":" + link;
        if (link.startsWith("/"))
            return origin ? origin[1] + link : link;
        return base.replace(/[^\/]*$/, "") + link;
    }

    function _date(s) {
        if (!s)
            return 0;
        s = s.trim();
        const months = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };
        const zones = { ut: 0, utc: 0, gmt: 0, z: 0, est: -5, edt: -4, cst: -6, cdt: -5, mst: -7, mdt: -6, pst: -8, pdt: -7 };
        const r = /(\d{1,2})\s+([a-z]{3})[a-z]*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[a-z]+)?/i.exec(s);
        if (r && months[r[2].toLowerCase()] !== undefined) {
            const year = r[3].length === 2 ? 2000 + parseInt(r[3]) : parseInt(r[3]);
            let offset = 0;
            if (r[7] && /^[+-]/.test(r[7]))
                offset = (r[7][0] === "-" ? -1 : 1) * (parseInt(r[7].slice(1, 3)) * 60 + parseInt(r[7].slice(3, 5)));
            else if (r[7])
                offset = (zones[r[7].toLowerCase()] || 0) * 60;
            return Date.UTC(year, months[r[2].toLowerCase()], parseInt(r[1]), parseInt(r[4]), parseInt(r[5]), parseInt(r[6] || 0)) - offset * 60000;
        }
        const t = Date.parse(s);
        return isNaN(t) ? 0 : t;
    }

    readonly property var view: {
        const nowMs = store.now.getTime(), checked = store.lastChecked;
        const byUrl = {};
        for (const f of store.feeds)
            byUrl[f.url] = f;
        return store.config.map(c => {
            let catFresh = 0;
            const feeds = c.feeds.map(def => {
                const f = byUrl[def.url] || { posts: [], error: "" };
                const title = def.name || f.title || def.url;
                const posts = (f.posts || [])
                    .filter(p => !c.clear || nowMs - p.time < c.clear)
                    .map(p => Object.assign({}, p, {
                        feed: title,
                        fresh: p.seen > checked && (!c.markRead || nowMs - p.seen < c.markRead)
                    }));
                const fresh = posts.filter(p => p.fresh).length;
                catFresh += fresh;
                return { id: def.url, url: def.url, title: title, error: f.error || "", posts: posts, fresh: fresh };
            });
            return Object.assign({}, c, { feeds: feeds, fresh: catFresh });
        });
    }

    readonly property var newPosts: {
        const out = [];
        for (const c of store.view)
            for (const f of c.feeds)
                for (const p of f.posts)
                    if (p.fresh)
                        out.push(p);
        out.sort((a, b) => b.time - a.time);
        return out;
    }

    readonly property int totalNew: newPosts.length
    readonly property int counterNew: view.reduce((n, c) => n + (c.counter ? c.fresh : 0), 0)

    function ago(t) {
        const s = Math.max(0, (store.now.getTime() - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    function since(t) {
        if (!t) return "never";
        const a = ago(t);
        return a === "now" ? "just now" : a + " ago";
    }
}
