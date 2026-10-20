.pragma library

// Geometry and user choices live for the session, independently of the bounded
// markdown and image caches and independently of delegate lifetimes.
var _sessions = {};

function entry(session, id) {
    var key = "$" + session;
    if (!_sessions[key]) _sessions[key] = {};
    var messages = _sessions[key];
    key = "$" + id;
    if (!messages[key]) messages[key] = {height: 0, signature: "", blocks: [], expanded: null};
    return messages[key];
}

function version(text) {
    var hash = 5381;
    for (var i = 0; i < text.length; ++i)
        hash = ((hash << 5) + hash + text.charCodeAt(i)) >>> 0;
    return text.length + ":" + hash;
}
