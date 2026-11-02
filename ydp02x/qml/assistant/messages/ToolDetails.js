.pragma library

function stateLabel(state) {
    var names = {preparing: "准备中", pending: "待执行", running: "执行中",
                 searching: "搜索中", done: "已完成", error: "失败", cancelled: "已取消"};
    return names[state] || "处理中";
}
function stateColor(state) {
    return state === "done" ? "#76C99B" : state === "error" ? "#F18B87"
         : state === "cancelled" ? "#9AA9B7" : state === "pending" ? "#E8BC74" : "#81B6E6";
}
function toolLabel(name) {
    var names = {shell_exec: "Shell 命令", web_search: "网络搜索", web_search_call: "网络搜索",
                 image_generation_call: "图像生成", code_interpreter_call: "代码执行",
                 file_search_call: "文件搜索"};
    return names[name] || name || "工具调用";
}
function entries(json, text, state, result) {
    try {
        var value = JSON.parse(json);
        if (Array.isArray(value) && value.length) return value;
    } catch (e) {}
    return [{name: "", text: text, state: state, result: result}];
}

// A bounded tree keeps object/array ownership visible on the small screen.
// Deep or large structures retain their original JSON rather than losing fields.
function treeRows(value) {
    var rows = [];
    function walk(node, label, depth) {
        if (rows.length > 200) throw new Error("large");
        var object = node !== null && typeof node === "object";
        var keys = object ? Object.keys(node) : [];
        var array = Array.isArray(node);
        rows.push({label: label, depth: depth, group: object,
                   value: object ? (array ? "数组 · " : "对象 · ") + keys.length + " 项"
                                 : node === null ? "null" : String(node)});
        if (object && depth >= 5 && keys.length) {
            rows.push({label: "内容", depth: depth + 1, group: false, value: JSON.stringify(node, null, 2)});
        } else {
            for (var i = 0; i < keys.length; ++i)
                walk(node[keys[i]], array ? "[" + keys[i] + "]" : keys[i], depth + 1);
        }
    }
    walk(value, Array.isArray(value) ? "列表" : "数据", 0);
    return rows;
}
function rows(raw, shellResult) {
    if (raw === undefined || raw === null || raw === "")
        return [{label: "", depth: 0, group: false, value: "暂无内容"}];
    var value = raw;
    if (typeof raw === "string") {
        try { value = JSON.parse(raw); } catch (e) {}
    }
    if (typeof value === "object" && value !== null) {
        try { return treeRows(value); }
        catch (e) { return [{label: "完整数据", depth: 0, group: false, value: JSON.stringify(value, null, 2)}]; }
    }
    var text = String(raw);
    if (text.indexOf("网络搜索结果（查询:") === 0) {
        var pattern = /(?:^|\n)(\d+)\. ([^\n]*)\n[ \t]+(https?:\/\/[^\n]+)\n/g;
        var matches = [], item;
        while ((item = pattern.exec(text)) !== null)
            matches.push({start: item.index, end: pattern.lastIndex, number: item[1], title: item[2], url: item[3]});
        if (matches.length) {
            var search = [{label: "搜索", depth: 0, group: false, value: text.slice(0, matches[0].start).trim()}];
            for (var i = 0; i < matches.length; ++i) {
                var hit = matches[i];
                search.push({label: "结果 " + hit.number, depth: 0, group: true, value: hit.title});
                search.push({label: "来源", depth: 1, group: false, value: hit.url});
                var content = text.slice(hit.end, i + 1 < matches.length ? matches[i + 1].start : text.length).trim();
                if (content) search.push({label: "摘要与内容", depth: 1, group: false, value: content});
            }
            return search;
        }
    }
    if (shellResult) {
        // Parse the text envelope emitted by Backend::shellResultText.
        // Use the final stderr marker so earlier copies remain in stdout.
        var match = /^(Exit code: (-?\d+)\n|命令超时（[^\n]+）[。]?\n)/.exec(text);
        if (match) {
            var result = [{label: match[2] !== undefined ? "退出码" : "执行状态",
                           depth: 0, group: false,
                           value: match[2] !== undefined ? match[2] : match[1].trim()}];
            var rest = text.slice(match[0].length);
            var stdout = rest.indexOf("stdout:\n");
            var stderr = rest.lastIndexOf("\nstderr:\n");
            if (rest.indexOf("stderr:\n") === 0) stderr = 0;
            if (stdout > 0) result.push({label: "状态说明", depth: 0, group: false, value: rest.slice(0, stdout).trim()});
            if (stdout >= 0) result.push({label: "标准输出", depth: 0, group: false,
                value: rest.slice(stdout + 8, stderr >= 0 ? stderr : rest.length).trim()});
            if (stderr >= 0) result.push({label: "错误输出", depth: 0, group: false,
                value: rest.slice(stderr + (stderr === 0 ? 8 : 9)).trim()});
            if (stdout < 0 && stderr < 0 && rest.trim())
                result.push({label: "状态说明", depth: 0, group: false, value: rest.trim()});
            return result;
        }
    }
    return [{label: "", depth: 0, group: false, value: text}];
}
