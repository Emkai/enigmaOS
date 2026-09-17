pragma Singleton

// TodoStore.qml — the bar's todo list and its on-disk store.
//
// Tasks live in ~/.cache/engimaos_todo/tasks.json as plain JSON so the file
// stays hand-editable:
//
//   { "version": 1, "tasks": [ { id, text, desc, due, done, created, completed } ] }
//
// "desc" is free-form multi-line notes on the task, "" when there are none.
// "due" is a local-time stamp — "YYYY-MM-DD" for a whole day or
// "YYYY-MM-DDTHH:MM" for a specific time, "" for no deadline. The file is
// watched, so editing it by hand updates the bar without a reload; our own
// writes come back through that same watch and _adopt() ignores them.
//
// Deadline *input* is free-form (see parseDue): "fri", "tmr 17:00", "+3d",
// "23 sep", "2026-09-23". The UI parses with parseDue() and only stores the
// normalised stamp, so everything downstream compares plain sortable strings.
//
// Why the pragma sits alone on line 1: quickshell's singleton scanner only
// reads a file up to the first opening brace and doesn't skip comments, so the
// JSON sketch above would hide a pragma placed below it; it also wants the line
// bare, so no trailing comment. Miss either and this registers as an ordinary
// type whose properties all read as undefined.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: store

    readonly property string dir: Quickshell.env("HOME") + "/.cache/engimaos_todo"
    readonly property string path: dir + "/tasks.json"

    // Canonical list, in file order. Always replaced wholesale — these are plain
    // JS objects inside a `var` property, so mutating one in place emits nothing.
    property var tasks: []

    // Ticks so deadline labels and colours age on their own. Deadlines resolve to
    // minutes at finest, so a 30s tick is enough to keep "today 17:00" honest.
    property date now: new Date()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: store.now = new Date() }

    // Open tasks sort by deadline (soonest first, undated last); done tasks by
    // most recently completed.
    readonly property var openTasks: {
        const list = store.tasks.filter(t => !t.done);
        list.sort(function (a, b) {
            const da = store.dueDate(a.due);
            const db = store.dueDate(b.due);
            if (da && db) return da - db;
            if (da) return -1;
            if (db) return 1;
            return String(a.created).localeCompare(String(b.created));
        });
        return list;
    }

    readonly property var doneTasks: {
        const list = store.tasks.filter(t => t.done);
        list.sort((a, b) => String(b.completed).localeCompare(String(a.completed)));
        return list;
    }

    readonly property int openCount: openTasks.length

    readonly property int overdueCount: {
        let n = 0;
        for (const t of store.tasks)
            if (!t.done && store.dueTone(t.due, store.now) === "overdue")
                n++;
        return n;
    }

    readonly property int dueTodayCount: {
        let n = 0;
        for (const t of store.tasks)
            if (!t.done && store.dueTone(t.due, store.now) === "today")
                n++;
        return n;
    }

    // ---------------- mutations ----------------

    // dueInput is anything parseDue accepts; desc is optional multi-line notes.
    // Returns false (and changes nothing) for empty text or an unparseable
    // deadline.
    function add(text, dueInput, desc) {
        const t = String(text === undefined || text === null ? "" : text).trim();
        if (t === "")
            return false;
        const due = store.parseDue(dueInput);
        if (due === null)
            return false;
        const next = store.tasks.slice();
        next.push({
            id: store._newId(),
            text: t,
            desc: store._cleanDesc(desc),
            due: due,
            done: false,
            created: store._stamp(new Date()),
            completed: ""
        });
        store.tasks = next;
        store._save();
        return true;
    }

    function toggle(id) {
        const next = store.tasks.map(function (t) {
            if (t.id !== id)
                return t;
            const done = !t.done;
            return Object.assign({}, t, { done: done, completed: done ? store._stamp(new Date()) : "" });
        });
        store.tasks = next;
        store._save();
    }

    function remove(id) {
        store.tasks = store.tasks.filter(t => t.id !== id);
        store._save();
    }

    function setDue(id, dueInput) {
        const due = store.parseDue(dueInput);
        if (due === null)
            return false;
        store.tasks = store.tasks.map(t => t.id === id ? Object.assign({}, t, { due: due }) : t);
        store._save();
        return true;
    }

    // Deadline and notes in one write — the row editor commits both together and
    // has no reason to leave two versions of the file behind.
    function edit(id, dueInput, desc) {
        const due = store.parseDue(dueInput);
        if (due === null)
            return false;
        const d = store._cleanDesc(desc);
        store.tasks = store.tasks.map(t => t.id === id ? Object.assign({}, t, { due: due, desc: d }) : t);
        store._save();
        return true;
    }

    // Notes are free-form, so there is nothing to reject — "" just clears them.
    function setDesc(id, desc) {
        const d = store._cleanDesc(desc);
        store.tasks = store.tasks.map(t => t.id === id ? Object.assign({}, t, { desc: d }) : t);
        store._save();
    }

    function setText(id, text) {
        const t = String(text === undefined || text === null ? "" : text).trim();
        if (t === "")
            return false;
        store.tasks = store.tasks.map(x => x.id === id ? Object.assign({}, x, { text: t }) : x);
        store._save();
        return true;
    }

    function clearDone() {
        store.tasks = store.tasks.filter(t => !t.done);
        store._save();
    }

    // ---------------- deadline parsing ----------------

    readonly property var _weekdayNames: ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    readonly property var _monthNames: ["jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"]

    // Free-form deadline -> "" (none) | "YYYY-MM-DD" | "YYYY-MM-DDTHH:MM" | null (invalid).
    // Already-normalised stamps pass straight through, so callers can hand back
    // whatever they got from us.
    function parseDue(input) {
        const trimmed = String(input === undefined || input === null ? "" : input).trim();
        if (trimmed === "")
            return "";

        const iso = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})(?:[t ](\d{2}):(\d{2}))?$/i);
        if (iso) {
            const d = store._mkDate(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3]));
            if (!d)
                return null;
            if (iso[4] === undefined)
                return store._fmtDate(d);
            if (Number(iso[4]) > 23 || Number(iso[5]) > 59)
                return null;
            return store._fmtDate(d) + "T" + iso[4] + ":" + iso[5];
        }

        const raw = trimmed.toLowerCase();
        if (raw === "none" || raw === "clear" || raw === "-" || raw === "x")
            return "";

        // Peel off a trailing time. It must carry a colon ("fri 17:00") or an "@"
        // ("fri@17") — a bare number is a day of the month, not an hour.
        let body = raw;
        let hh = -1;
        let mm = 0;
        let m = raw.match(/(?:^|\s)(\d{1,2}):(\d{2})$/);
        if (!m)
            m = raw.match(/@\s*(\d{1,2})(?::(\d{2}))?$/);
        if (m) {
            hh = Number(m[1]);
            mm = m[2] === undefined ? 0 : Number(m[2]);
            if (hh > 23 || mm > 59)
                return null;
            body = raw.slice(0, raw.length - m[0].length).trim();
        }

        const base = new Date();
        const d = store._parseDateBody(body, base);
        if (!d)
            return null;
        if (hh < 0)
            return store._fmtDate(d);
        // A bare time ("17:00") means the next time it comes round, so roll to
        // tomorrow once today's has passed.
        if (body === "" && (hh < base.getHours() || (hh === base.getHours() && mm <= base.getMinutes())))
            d.setDate(d.getDate() + 1);
        return store._fmtDate(d) + "T" + store._pad2(hh) + ":" + store._pad2(mm);
    }

    function _parseDateBody(body, base) {
        const today = new Date(base.getFullYear(), base.getMonth(), base.getDate());

        if (body === "" || body === "today" || body === "tod" || body === "now")
            return today;
        if (body === "tomorrow" || body === "tmr" || body === "tom" || body === "tmw") {
            today.setDate(today.getDate() + 1);
            return today;
        }

        // Relative: "+3", "+3d", "3d", "2w". A bare "3" is the 3rd of the month.
        let m = body.match(/^\+(\d+)\s*([dw]?)$/);
        if (!m)
            m = body.match(/^(\d+)\s*([dw])$/);
        if (m) {
            today.setDate(today.getDate() + Number(m[1]) * (m[2] === "w" ? 7 : 1));
            return today;
        }

        // "2026-9-23" — full date. The canonical form is caught earlier by
        // parseDue, this picks up the sloppier ones ("2026-09-23 8:00").
        m = body.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
        if (m)
            return store._mkDate(Number(m[1]), Number(m[2]) - 1, Number(m[3]));

        // "9-23" — month-day, ISO order, rolling into next year once past.
        m = body.match(/^(\d{1,2})-(\d{1,2})$/);
        if (m)
            return store._nextOccurrence(base.getFullYear(), Number(m[1]) - 1, Number(m[2]), today, 12);

        // "23" — day of this month, rolling into next month once past.
        m = body.match(/^(\d{1,2})$/);
        if (m)
            return store._nextOccurrence(base.getFullYear(), base.getMonth(), Number(m[1]), today, 1);

        // "23 sep" / "sep 23".
        let day = -1;
        let mon = -1;
        m = body.match(/^(\d{1,2})\s+([a-z]+)$/);
        if (m) {
            day = Number(m[1]);
            mon = store._monthIndex(m[2]);
        } else {
            m = body.match(/^([a-z]+)\s+(\d{1,2})$/);
            if (m) {
                mon = store._monthIndex(m[1]);
                day = Number(m[2]);
            }
        }
        if (day > 0 && mon >= 0)
            return store._nextOccurrence(base.getFullYear(), mon, day, today, 12);

        // Weekday name — the coming one; "mon" on a Monday means next Monday.
        const wd = store._weekdayIndex(body);
        if (wd >= 0) {
            let ahead = (wd - today.getDay() + 7) % 7;
            if (ahead === 0)
                ahead = 7;
            today.setDate(today.getDate() + ahead);
            return today;
        }

        return null;
    }

    // The given day, pushed forward by monthStep months if it has already gone by.
    function _nextOccurrence(year, month, day, today, monthStep) {
        let d = store._mkDate(year, month, day);
        if (d && d < today)
            d = store._mkDate(year, month + monthStep, day);
        return d;
    }

    // Builds a date, normalising out-of-range months, and rejects days that don't
    // exist in the resulting month (31 feb).
    function _mkDate(year, month, day) {
        if (day < 1 || day > 31)
            return null;
        const y = year + Math.floor(month / 12);
        const mo = ((month % 12) + 12) % 12;
        const d = new Date(y, mo, day);
        if (d.getFullYear() !== y || d.getMonth() !== mo || d.getDate() !== day)
            return null;
        return d;
    }

    function _monthIndex(name) {
        for (let i = 0; i < store._monthNames.length; i++)
            if (name.startsWith(store._monthNames[i]))
                return i;
        return -1;
    }

    function _weekdayIndex(name) {
        if (name.length < 3)
            return -1;
        for (let i = 0; i < store._weekdayNames.length; i++)
            if (name.startsWith(store._weekdayNames[i]))
                return i;
        return -1;
    }

    // ---------------- deadline presentation ----------------

    function dueDate(dueStr) {
        const m = String(dueStr === undefined || dueStr === null ? "" : dueStr)
            .match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/);
        if (!m)
            return null;
        return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
            m[4] === undefined ? 0 : Number(m[4]),
            m[5] === undefined ? 0 : Number(m[5]));
    }

    function dueHasTime(dueStr) {
        return /T\d{2}:\d{2}$/.test(String(dueStr === undefined || dueStr === null ? "" : dueStr));
    }

    // "none" | "overdue" | "today" | "soon" (tomorrow) | "later"
    function dueTone(dueStr, ref) {
        const d = store.dueDate(dueStr);
        if (!d)
            return "none";
        const days = store._dayDiff(ref, d);
        if (days < 0 || (days === 0 && store.dueHasTime(dueStr) && d < ref))
            return "overdue";
        if (days === 0)
            return "today";
        if (days === 1)
            return "soon";
        return "later";
    }

    // Compact, relative where that reads better than a date: "2d late", "today
    // 17:00", "tmr", "fri 09:00", "23 sep".
    function dueLabel(dueStr, ref) {
        const d = store.dueDate(dueStr);
        if (!d)
            return "";
        const days = store._dayDiff(ref, d);
        const time = store.dueHasTime(dueStr) ? store._pad2(d.getHours()) + ":" + store._pad2(d.getMinutes()) : "";
        if (days < 0)
            return (-days) + "d late";
        if (days === 0)
            return time === "" ? "today" : "today " + time;
        if (days === 1)
            return time === "" ? "tomorrow" : "tmr " + time;
        if (days < 7)
            return store._weekdayNames[d.getDay()] + (time === "" ? "" : " " + time);
        return d.getDate() + " " + store._monthNames[d.getMonth()];
    }

    function _dayDiff(from, to) {
        const a = new Date(from.getFullYear(), from.getMonth(), from.getDate());
        const b = new Date(to.getFullYear(), to.getMonth(), to.getDate());
        return Math.round((b - a) / 86400000);
    }

    function _pad2(n) { return String(n).padStart(2, "0"); }

    function _fmtDate(d) {
        return d.getFullYear() + "-" + store._pad2(d.getMonth() + 1) + "-" + store._pad2(d.getDate());
    }

    function _stamp(d) {
        return store._fmtDate(d) + "T" + store._pad2(d.getHours()) + ":" + store._pad2(d.getMinutes());
    }

    // Keeps the line breaks that make notes worth having, drops the blank edges
    // a textarea collects, and normalises CRLF out of hand-edited files.
    function _cleanDesc(desc) {
        return String(desc === undefined || desc === null ? "" : desc).replace(/\r\n/g, "\n").trim();
    }

    function _newId() {
        return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1679616).toString(36).padStart(4, "0");
    }

    // ---------------- persistence ----------------

    property string _lastWritten: ""
    property bool _dirReady: false
    property bool _savePending: false // edited, not yet handed to FileView
    property bool _writing: false     // handed to FileView, write not confirmed

    // Reads are asynchronous, so one started before an edit can land after it.
    // Anything arriving while we hold unflushed or in-flight changes is stale by
    // definition and gets dropped — letting it through rolls the list back, and
    // the next save then persists the rolled-back version. A missing file is the
    // normal first-run state and must likewise never clear what we already hold.
    FileView {
        id: file
        path: store.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: store._adopt(text())
        onSaved: store._writing = false
        onSaveFailed: function (error) {
            store._writing = false;
            console.warn("todo: could not write " + store.path + ": " + FileViewError.toString(error));
        }
        onLoadFailed: function (error) {
            if (error !== FileViewError.FileNotFound)
                console.warn("todo: could not read " + store.path + ": " + FileViewError.toString(error));
        }
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", store.dir]
        onExited: {
            store._dirReady = true;
            if (store._savePending)
                store._flush();
        }
    }

    Component.onCompleted: {
        mkdirProc.running = true;
        // watchChanges happens to trigger an initial read, but FileView otherwise
        // only reads on demand and nothing here touches text() directly, so ask
        // for the first read outright rather than leaning on that.
        file.reload();
    }

    function _adopt(text) {
        if (store._savePending || store._writing)
            return; // predates changes of ours that haven't reached the file yet
        if (text === store._lastWritten)
            return; // our own write, echoed back by the file watcher
        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            return; // half-written or hand-mangled: keep what we have
        }
        const list = Array.isArray(parsed) ? parsed
            : (parsed && Array.isArray(parsed.tasks) ? parsed.tasks : null);
        if (!list)
            return;
        store.tasks = list.map(t => store._normalize(t)).filter(t => t !== null);
    }

    function _normalize(t) {
        if (!t || typeof t.text !== "string" || t.text.trim() === "")
            return null;
        const due = typeof t.due === "string" ? store.parseDue(t.due) : "";
        return {
            id: typeof t.id === "string" && t.id !== "" ? t.id : store._newId(),
            text: t.text.trim(),
            desc: store._cleanDesc(t.desc),
            due: due === null ? "" : due,
            done: t.done === true,
            created: typeof t.created === "string" ? t.created : "",
            completed: typeof t.completed === "string" ? t.completed : ""
        };
    }

    function _save() {
        store._savePending = true;
        if (store._dirReady)
            store._flush();
        else if (!mkdirProc.running)
            mkdirProc.running = true;
    }

    function _flush() {
        store._savePending = false;
        store._writing = true;
        store._lastWritten = JSON.stringify({ version: 1, tasks: store.tasks }, null, 2) + "\n";
        file.setText(store._lastWritten);
    }
}
