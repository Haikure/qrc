import QtQuick 2.12
import com.youdao.pen 1.0

import "../utils"

Item {
    id: root
    anchors.fill: parent

    property var _entries: []
    property var _cache: ({})
    property var _pending: null
    property var _afterTransitionCallbacks: []
    property int _requestSequence: 0
    property int _visualSequence: 0
    property bool _handlingBack: false
    property bool _ignoreAnimationStop: false
    property string _transitionKind: ""
    property var _incoming: null
    property var _outgoing: null
    property var _outgoingEntry: null

    property var currentItem: null
    property var currentRoute: null
    property var backgroundItem: null
    // 整屏滑动。原来是 12px / 180ms：12px 只有屏宽的百分之几，平均 0.067px/ms、
    // 一帧走 3px —— 低于能被感知为"滑动"的门槛，看上去只是抖了一下。
    // 位移也必须等于屏宽：只滑一半的话，页面在动画结束时还有大半在屏上，
    // 紧接着被 _disposeEntry() 隐藏，必然看到跳变（位移越大跳得越狠）；
    // 整屏位移是在页面完全移出屏幕之后才隐藏，没有跳变。
    // 时长随之从 180ms 放宽到 240ms（320px ⇒ 平均 1.33px/ms），12px 时代的
    // 180ms 摊到整屏上太赶。
    property int transitionDuration: 240
    // 出栈单独用更短的时长：退出比进入更不该让人等，而且 InQuad 这类加速曲线
    // 的加速度要靠"总时长短"才显得出来（见 popAnimation 注释）。
    property int popDuration: 180
    // YNavigator 本身满屏，root.width 就是屏宽。
    property real transitionDistance: root.width
    // 整屏滑动时不能再让页面半透明：0.96 会让整个页面透出底下的旧页，
    // 形成重影。push/pop 都靠位移表达层级，不需要透明度帮忙。
    property real transitionStartOpacity: 1.0
    readonly property int count: _entries.length
    readonly property bool canPop: count > 0 && !transitionRunning
    readonly property bool isShowing: currentItem !== null
    readonly property bool currentPopIdValid: isShowing
    property bool transitionRunning: false

    // Compatibility surface for callers being migrated from YPopLayer.
    readonly property alias popItemObject: root.currentItem
    readonly property alias stackDepth: root.count

    signal navigationStarted(string operation, string routeId)
    signal navigationFinished(string operation, string routeId)
    signal navigationFailed(string routeId)

    YRouteTable {
        id: routes
    }

    Component {
        id: pageHostComponent
        Item {
            id: pageHost
            anchors.fill: parent
            visible: false
            property alias transitionX: pageTranslate.x
            transform: Translate {
                id: pageTranslate
                x: 0
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: root.transitionRunning
        enabled: visible
        z: YUtils.visualZSequence + 1
        onPressed: mouse.accepted = true
        onReleased: mouse.accepted = true
        onClicked: mouse.accepted = true
    }

    ParallelAnimation {
        id: pushAnimation
        NumberAnimation {
            target: root._incoming
            property: "transitionX"
            from: root.transitionDistance
            to: 0
            duration: root.transitionDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root._incoming
            property: "opacity"
            from: root.transitionStartOpacity
            to: 1
            duration: root.transitionDuration
            easing.type: Easing.OutQuad
        }
        onStopped: root._animationStopped()
    }

    ParallelAnimation {
        id: popAnimation
        // 入栈时只有进入页在动（+distance -> 0），被它盖住的页面原地不动。
        // 出栈必须是它的镜像：只有被弹出的页在动（0 -> +distance），
        // 回来的页面原地不动。
        //
        // 别再写成"父页 -distance -> 0 + 子页 0 -> +distance"两页同动：
        // 两条曲线相同，两页的相对位移就恒等于 0，屏幕上看到的不是
        // "子页滑走、父页露出来"，而是整块画面平移 —— 没有层次。
        //
        // 曲线必须是加速曲线（In 系），不是减速曲线（Out 系）：出栈是"把页面
        // 甩出去"，速度该在末端最大；照抄入栈的减速曲线会让页面在快离开屏幕
        // 时几乎停住（最后 20ms 只走 0.2px），观感上等于没有缓动。
        //
        // 选 InQuad 而不是严格时间反演 InCubic，因为平均速度是恒定的
        // （distance / duration），末端越比值越大、起步就越接近 0：
        //   曲线         起步(每20ms)  末端(px/ms)  末端/平均
        //   InCubic 240     0.19px       3.68        2.76
        //   InQuad  240     2.22px       2.56        1.92
        //   InQuad  180     3.95px       3.36        1.89   <-- 现在用的
        //   OutCubic 240   73.5px        0.01        0.01
        // InCubic 末端只比 InQuad 快 10%，起步却慢 20 倍；把时长压到 180ms
        // 之后，InQuad 的末端速度已经追平 InCubic@240，起步仍有近 4px/20ms。
        // 时长用 popDuration（比入栈的 240ms 短）：退出本来就不该让人等。
        NumberAnimation {
            target: root._outgoing
            property: "transitionX"
            from: 0
            to: root.transitionDistance
            duration: root.popDuration
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: root._incoming
            property: "opacity"
            from: root.transitionStartOpacity
            to: 1
            duration: root.popDuration
            easing.type: Easing.OutQuad
        }
        onStopped: root._animationStopped()
    }

    Component.onCompleted: {
        // Legacy nested pop layers use this as their incubation parent.
        if (!YUtils.stackView)
            YUtils.stackView = root;
    }

    function routeIdForLegacy(qmlName) {
        return routes.resolveLegacy(qmlName).routeId;
    }

    function routeForPageIndex(pageIndex) {
        return routes.routeForPageIndex(pageIndex);
    }

    function afterTransition(callback) {
        if (typeof callback !== "function")
            return;
        if (!transitionRunning) {
            callback();
            return;
        }
        var callbacks = _afterTransitionCallbacks.slice();
        callbacks.push(callback);
        _afterTransitionCallbacks = callbacks;
    }

    function _runAfterTransitionCallbacks() {
        if (_afterTransitionCallbacks.length === 0)
            return;
        var callbacks = _afterTransitionCallbacks.slice();
        _afterTransitionCallbacks = [];
        Qt.callLater(function() {
            for (var i = 0; i < callbacks.length; ++i) {
                try {
                    callbacks[i]();
                } catch (error) {
                    console.warn("YNavigator deferred navigation failed:", error);
                }
            }
        });
    }

    function _setEntries(entries) {
        _entries = entries;
        currentItem = entries.length > 0 ? entries[entries.length - 1].item : null;
        currentRoute = entries.length > 0 ? entries[entries.length - 1].route : null;
    }

    function _applyProperties(item, properties) {
        if (!item || !properties)
            return;
        Object.keys(properties).forEach(function(key) {
            try {
                item[key] = properties[key];
            } catch (error) {
                console.warn("YNavigator property update failed:", key, error);
            }
        });
    }

    function _setManaged(item, managed) {
        if (!item)
            return;
        if (item.hasOwnProperty("navigationManaged"))
            item.navigationManaged = managed;
        if (item.hasOwnProperty("navigator"))
            item.navigator = managed ? root : null;
    }

    function _publishPageIndex(entry) {
        if (!entry || !entry.item)
            return;
        var pageIndex = entry.route.pageIndex;
        if (pageIndex < 0 && entry.item.hasOwnProperty("pageIndex"))
            pageIndex = entry.item.pageIndex;
        if (pageIndex >= 0 && qmlGlobal.currentPageIndex !== pageIndex)
            qmlGlobal.currentPageIndex = pageIndex;
    }

    function _connectEntry(entry) {
        var item = entry.item;
        if (!item || !item.hasOwnProperty("backButtonClicked"))
            return;

        entry.backCallback = function() {
            if (root._handlingBack || root.currentItem !== item)
                return;
            root._beginPop(entry, false);
        };
        item.backButtonClicked.connect(entry.backCallback);

        entry.destructionCallback = function() {
            if (entry.disposed)
                return;
            var wasCurrent = root.currentItem === item;
            entry.disposed = true;
            var index = root._entries.indexOf(entry);
            if (index >= 0) {
                var remaining = root._entries.slice();
                remaining.splice(index, 1);
                root._setEntries(remaining);
            }
            if (wasCurrent) {
                if (root.currentItem)
                    root._publishPageIndex(root._entries[root.count - 1]);
                else
                    qmlGlobal.currentPageIndex = YEnum.PageIndex.NonePage;
            }
        };
        item.Component.destruction.connect(entry.destructionCallback);
    }

    function _disconnectEntry(entry) {
        if (!entry || !entry.item)
            return;
        if (entry.backCallback && entry.item.hasOwnProperty("backButtonClicked")) {
            try {
                entry.item.backButtonClicked.disconnect(entry.backCallback);
            } catch (error) {}
        }
        if (entry.destructionCallback) {
            try {
                entry.item.Component.destruction.disconnect(entry.destructionCallback);
            } catch (error) {}
        }
        entry.backCallback = null;
        entry.destructionCallback = null;
    }

    // Cached pages can be destroyed by Qt outside normal navigation. Remove
    // their stale entry so the next navigation creates a fresh page.
    function _watchCachedEntry(entry) {
        if (!entry || !entry.item || entry.cacheDestructionCallback)
            return;
        entry.cacheDestructionCallback = function() {
            if (_cache[entry.route.routeId] === entry)
                delete _cache[entry.route.routeId];
            entry.cacheDestructionCallback = null;
            entry.disposed = true;
        };
        entry.item.Component.destruction.connect(entry.cacheDestructionCallback);
    }

    function _disconnectCachedEntry(entry) {
        if (!entry || !entry.item || !entry.cacheDestructionCallback)
            return;
        try {
            entry.item.Component.destruction.disconnect(entry.cacheDestructionCallback);
        } catch (error) {}
        entry.cacheDestructionCallback = null;
    }

    function _disposeEntry(entry, cachePolicy) {
        if (!entry || entry.disposed)
            return;
        entry.disposed = true;
        _disconnectEntry(entry);
        if (entry.item && typeof entry.item.navigationDeactivated === "function")
            entry.item.navigationDeactivated();
        _setManaged(entry.item, false);
        if (entry.item)
            entry.item.visible = false;
        if (entry.host) {
            entry.host.visible = false;
            entry.host.transitionX = 0;
            entry.host.opacity = 1;
        }
        if (cachePolicy === "keepAlive") {
            _cache[entry.route.routeId] = entry;
            _watchCachedEntry(entry);
        } else if (entry.item) {
            // Keep the visual host alive until the page root has finished
            // destruction. Qt 5 may reevaluate parent.top/left bindings while
            // detaching children from a host that is destroyed first.
            var host = entry.host;
            var destroyHost = function() {
                if (!host)
                    return;
                try {
                    host.destroy(1);
                } catch (error) {
                    console.warn("YNavigator host cleanup failed:", error);
                }
                host = null;
            };
            try {
                entry.item.Component.destruction.connect(destroyHost);
                entry.item.destroy(1);
            } catch (error) {
                console.warn("YNavigator page cleanup failed:", error);
                destroyHost();
            }
        }
    }

    function _cachePolicy(route, requestedCache) {
        if (requestedCache === true)
            return "keepAlive";
        if (requestedCache === false)
            return "destroy";
        return route.cachePolicy || "destroy";
    }

    function _showItem(entry, resumed) {
        _setManaged(entry.item, true);
        _visualSequence += 1;
        if (!resumed || YUtils.currentPopId.length === 0)
            entry.host.z = YUtils.nextVisualZ();
        entry.host.visible = true;
        if (entry.item.hasOwnProperty("animationEnabled"))
            entry.item.animationEnabled = true;
        if (typeof entry.item.show === "function")
            entry.item.show();
        else
            entry.item.visible = true;
        entry.item.visible = true;
        if (typeof entry.item.navigationActivated === "function")
            entry.item.navigationActivated(resumed === true);
    }

    function _startPush(entry, outgoing, animated) {
        _incoming = entry.host;
        _outgoing = outgoing ? outgoing.host : null;
        _outgoingEntry = outgoing;
        if (outgoing) {
            outgoing.host.transitionX = 0;
            outgoing.host.opacity = 1;
            outgoing.host.visible = true;
            outgoing.item.visible = true;
        } else if (backgroundItem) {
            backgroundItem.transitionX = 0;
            backgroundItem.opacity = 1;
            backgroundItem.visible = true;
        }
        _showItem(entry);
        _publishPageIndex(entry);
        transitionRunning = true;
        _transitionKind = "push";
        navigationStarted("push", entry.route.routeId);

        _incoming.transitionX = animated ? transitionDistance : 0;
        _incoming.opacity = animated ? transitionStartOpacity : 1;
        if (animated)
            pushAnimation.start();
        else
            _animationStopped();
    }

    function _startPop(entry, incoming, animated) {
        _incoming = incoming ? incoming.host : backgroundItem;
        _outgoing = entry.host;
        _outgoingEntry = entry;
        entry.host.transitionX = 0;
        entry.host.opacity = 1;
        entry.host.visible = true;
        entry.item.visible = true;
        transitionRunning = true;
        _transitionKind = "pop";
        navigationStarted("pop", entry.route.routeId);

        if (incoming) {
            _showItem(incoming, true);
            _publishPageIndex(incoming);
        } else {
            // 返回首页这条路不再在这里隐藏被弹出的页面：它还要播完退出动画，
            // 隐藏交给 _animationStopped() -> _disposeEntry()。
            // currentPageIndex 同理往后挪——页面在屏幕上还活着的时候，
            // 全局页码先跳成 NonePage 会让监听方看到自相矛盾的状态。
            if (_incoming)
                _incoming.visible = true;
        }
        // _showItem() 刚把进入页的 z 抬到最大，出栈时被弹出的页面
        // 必须盖在它上面，否则右移退出的动作会被父页整体遮住。
        entry.host.z = YUtils.nextVisualZ();
        if (_incoming) {
            // 父页原地不动 —— 入栈时它也是不动的，出栈才对得上。
            // 父页占满 0..width，子页滑出去露出的就是它，不会有缝。
            _incoming.transitionX = 0;
            _incoming.opacity = animated ? transitionStartOpacity : 1;
        }

        if (animated && _incoming)
            popAnimation.start();
        else
            _animationStopped();
    }

    function _animationStopped() {
        if (_ignoreAnimationStop)
            return;

        var kind = _transitionKind;
        var outgoing = _outgoing;
        var incoming = _incoming;
        transitionRunning = false;

        if (kind === "push") {
            if (outgoing) {
                outgoing.transitionX = 0;
                outgoing.opacity = 1;
                outgoing.visible = false;
            }
            if (_outgoingEntry && _outgoingEntry.item)
                _outgoingEntry.item.visible = false;
            if (backgroundItem)
                backgroundItem.visible = false;
            if (incoming) {
                incoming.transitionX = 0;
                incoming.opacity = 1;
                incoming.visible = true;
            }
        } else if (kind === "pop") {
            if (outgoing) {
                var popped = null;
                for (var i = 0; i < _entries.length; ++i) {
                    if (_entries[i].host === outgoing) {
                        popped = _entries[i];
                        break;
                    }
                }
                var remaining = _entries.slice();
                if (popped) {
                    remaining.splice(remaining.indexOf(popped), 1);
                    _setEntries(remaining);
                    _disposeEntry(popped, _cachePolicy(popped.route, popped.requestedCache));
                }
            }
            // 返回首页那条分支：全局页码要等退出动画播完、页面真正隐藏之后才置空。
            // 原先在 _startPop() 里就置空，于是有 180ms 的窗口「全局已无当前页、
            // 子页却还在屏幕上」——监听 currentPageIndexChanged 的 C++ 侧会拿到
            // 与画面不一致的状态。entries 空了就说明确实没有页面了。
            if (_entries.length === 0 && qmlGlobal.currentPageIndex !== YEnum.PageIndex.NonePage)
                qmlGlobal.currentPageIndex = YEnum.PageIndex.NonePage;
            if (incoming) {
                incoming.transitionX = 0;
                incoming.opacity = 1;
                incoming.visible = true;
            }
        }

        var routeId = currentRoute ? currentRoute.routeId : "";
        navigationFinished(kind, routeId);
        _incoming = null;
        _outgoing = null;
        _outgoingEntry = null;
        _transitionKind = "";
        _runAfterTransitionCallbacks();
    }

    function _cancelTransition() {
        if (!transitionRunning)
            return;
        _ignoreAnimationStop = true;
        pushAnimation.stop();
        popAnimation.stop();
        _ignoreAnimationStop = false;
        transitionRunning = false;
        _incoming = null;
        _outgoing = null;
        _outgoingEntry = null;
        _transitionKind = "";
        _afterTransitionCallbacks = [];
    }

    function _beginPop(entry, dispatchBackSignal) {
        if (transitionRunning || !entry || entry !== _entries[_entries.length - 1])
            return;

        if (dispatchBackSignal) {
            var current = entry.item;
            _handlingBack = true;
            try {
                if (current && current.hasOwnProperty("backButtonClicked"))
                    current.backButtonClicked();
            } catch (error) {
                console.warn("YNavigator back callback failed:", error);
            }
            _handlingBack = false;
        }

        var incoming = _entries.length > 1 ? _entries[_entries.length - 2] : null;
        _startPop(entry, incoming, true);
    }

    function pop() {
        if (transitionRunning || _entries.length === 0)
            return null;
        var entry = _entries[_entries.length - 1];
        _beginPop(entry, true);
        return entry.item;
    }

    function replaceLegacy(qmlName, properties, options) {
        if (_entries.length === 0)
            return null;

        var nextProperties = properties || {};
        var nextOptions = options || {};
        if (transitionRunning) {
            afterTransition(function() {
                root.replaceLegacy(qmlName, nextProperties, nextOptions);
            });
            return currentItem;
        }

        var entry = _entries[_entries.length - 1];
        _beginPop(entry, true);
        afterTransition(function() {
            root.pushLegacy(qmlName, nextProperties, nextOptions);
        });
        return entry.item;
    }

    function _finishCreated(route, properties, requestedCache, animated, sequence, component) {
        if (!_pending || _pending.sequence !== sequence || _requestSequence !== sequence) {
            try { component.destroy(); } catch (error) {}
            return null;
        }
        _pending = null;
        var host = pageHostComponent.createObject(root);
        var item = null;
        try {
            item = component.createObject(host, properties || {});
        } catch (error) {
            console.error("YNavigator page creation failed:", route.routeId, error);
        }
        try { component.destroy(); } catch (error) {}
        if (!item) {
            if (host)
                host.destroy(1);
            navigationFailed(route.routeId);
            return null;
        }

        item.visible = false;
        var entry = {
            "host": host,
            "item": item,
            "route": route,
            "requestedCache": requestedCache,
            "disposed": false,
            "backCallback": null,
            "destructionCallback": null,
            "cacheDestructionCallback": null
        };
        _applyProperties(item, properties);
        _connectEntry(entry);
        var entries = _entries.slice();
        var outgoing = entries.length > 0 ? entries[entries.length - 1] : null;
        entries.push(entry);
        _setEntries(entries);
        _startPush(entry, outgoing, animated);
        return item;
    }

    function _createAndPush(route, properties, requestedCache, animated) {
        _requestSequence += 1;
        var sequence = _requestSequence;
        if (_pending) {
            _pending.cancelled = true;
            try {
                if (_pending.callback)
                    _pending.component.statusChanged.disconnect(_pending.callback);
                _pending.component.destroy();
            } catch (error) {}
            _pending = null;
        }

        // Legacy callers configure the returned page immediately, so normal
        // navigation stays synchronous while preload() remains asynchronous.
        var component = Qt.createComponent(route.url);
        var pending = {
            "component": component,
            "sequence": sequence,
            "cancelled": false,
            "callback": null
        };
        _pending = pending;
        if (component.status === Component.Error) {
            _pending = null;
            console.error("YNavigator route error:", route.routeId, component.errorString());
            navigationFailed(route.routeId);
            try { component.destroy(); } catch (error) {}
            return null;
        }
        if (component.status === Component.Ready)
            return _finishCreated(route, properties, requestedCache, animated, sequence, component);

        pending.callback = function() {
            if (component.status === Component.Loading)
                return;
            try { component.statusChanged.disconnect(pending.callback); } catch (error) {}
            if (pending.cancelled)
                return;
            if (component.status === Component.Ready)
                _finishCreated(route, properties, requestedCache, animated, sequence, component);
            else {
                _pending = null;
                console.error("YNavigator route error:", route.routeId, component.errorString());
                navigationFailed(route.routeId);
                try { component.destroy(); } catch (error) {}
            }
        };
        component.statusChanged.connect(pending.callback);
        return null;
    }

    function push(routeId, properties, options) {
        return _pushResolved(routes.resolve(routeId), routeId, properties, options);
    }

    function _pushResolved(route, requestedRouteId, properties, options) {
        if (transitionRunning)
            return currentItem;

        if (!route) {
            navigationFailed(requestedRouteId);
            return null;
        }
        var config = options || {};
        var requestedCache = config.hasOwnProperty("cache") ? config.cache : undefined;
        var launchMode = config.launchMode || route.launchMode;
        var existingIndex = -1;
        if (launchMode === "singleTask") {
            for (var i = 0; i < _entries.length; ++i) {
                if (_entries[i].route.routeId === route.routeId) {
                    existingIndex = i;
                    break;
                }
            }
        }

        if (existingIndex >= 0) {
            var existing = _entries[existingIndex];
            if (existingIndex === _entries.length - 1) {
                _applyProperties(existing.item, properties);
                _publishPageIndex(existing);
                return existing.item;
            }
            var reordered = _entries.slice();
            reordered.splice(existingIndex, 1);
            reordered.push(existing);
            var outgoing = _entries[_entries.length - 1];
            _setEntries(reordered);
            _applyProperties(existing.item, properties);
            _startPush(existing, outgoing, config.animation !== false);
            return existing.item;
        }

        var cached = _cache[route.routeId];
        if (cached && (!cached.item || !cached.host)) {
            delete _cache[route.routeId];
            cached = null;
        }
        if (cached) {
            delete _cache[route.routeId];
            _disconnectCachedEntry(cached);
            cached.disposed = false;
            cached.requestedCache = requestedCache;
            _applyProperties(cached.item, properties);
            _connectEntry(cached);
            var cachedEntries = _entries.slice();
            var cachedOutgoing = cachedEntries.length > 0 ? cachedEntries[cachedEntries.length - 1] : null;
            cachedEntries.push(cached);
            _setEntries(cachedEntries);
            _startPush(cached, cachedOutgoing, config.animation !== false);
            return cached.item;
        }

        return _createAndPush(route, properties, requestedCache, config.animation !== false);
    }

    function pushLegacy(qmlName, properties, options) {
        var route = routes.resolveLegacy(qmlName);
        var config = options || {};
        var routeOptions = {
            "cache": config.hasOwnProperty("cache") ? config.cache : undefined,
            "animation": config.hasOwnProperty("animation") ? config.animation : true,
            "launchMode": config.launchMode || route.launchMode
        };
        return _pushResolved(route, route.routeId, properties, routeOptions);
    }

    function show(qmlName, animationEnabled, propertiesOrCache, legacyProperties) {
        var properties = legacyProperties;
        var cache = undefined;
        if (typeof propertiesOrCache === "boolean")
            cache = propertiesOrCache;
        else if (propertiesOrCache && typeof propertiesOrCache === "object")
            properties = propertiesOrCache;
        return pushLegacy(qmlName, properties, {
            "cache": cache,
            "animation": animationEnabled !== false
        });
    }

    function cacheShow(qmlName, animationEnabled, properties) {
        return pushLegacy(qmlName, properties, {
            "cache": true,
            "animation": animationEnabled !== false
        });
    }

    function showWithProperties(qmlName, properties) {
        return pushLegacy(qmlName, properties, { "animation": true });
    }

    function _preloadFinished(route, properties, component, incubator, host) {
        if (incubator.status !== Component.Ready || !incubator.object) {
            if (host)
                host.destroy(1);
            try { component.destroy(); } catch (error) {}
            return;
        }
        var item = incubator.object;
        item.visible = false;
        var entry = {
            "host": item.parent,
            "item": item,
            "route": route,
            "requestedCache": true,
            "disposed": false,
            "backCallback": null,
            "destructionCallback": null,
            "cacheDestructionCallback": null
        };
        _applyProperties(item, properties);
        _setManaged(item, false);
        _cache[route.routeId] = entry;
        _watchCachedEntry(entry);
        try { component.destroy(); } catch (error) {}
    }

    function preload(qmlName, properties) {
        var route = routes.resolveLegacy(qmlName);
        if (_cache[route.routeId])
            return;
        for (var i = 0; i < _entries.length; ++i) {
            if (_entries[i].route.routeId === route.routeId)
                return;
        }
        var component = Qt.createComponent(route.url, Component.Asynchronous);
        var finish = function() {
            try { component.statusChanged.disconnect(finish); } catch (error) {}
            if (component.status !== Component.Ready) {
                try { component.destroy(); } catch (error) {}
                return;
            }
            var host = pageHostComponent.createObject(root);
            var incubator = component.incubateObject(host, properties || {}, Qt.Asynchronous);
            if (incubator.status === Component.Ready)
                _preloadFinished(route, properties, component, incubator, host);
            else
                incubator.onStatusChanged = function() {
                    if (incubator.status === Component.Ready || incubator.status === Component.Error)
                        _preloadFinished(route, properties, component, incubator, host);
                };
        };
        if (component.status === Component.Ready)
            finish();
        else if (component.status === Component.Loading)
            component.statusChanged.connect(finish);
        else
            try { component.destroy(); } catch (error) {}
    }

    function closeCurrentPage() {
        return pop();
    }

    function closeAllPages() {
        resetToHome();
    }

    function closeAllPopPage() {
        resetToHome();
        YUtils.clearStackView();
    }

    function resetToHome() {
        _requestSequence += 1;
        _cancelTransition();
        if (_pending) {
            _pending.cancelled = true;
            try {
                if (_pending.callback)
                    _pending.component.statusChanged.disconnect(_pending.callback);
                _pending.component.destroy();
            } catch (error) {}
            _pending = null;
        }
        var entries = _entries.slice();
        _setEntries([]);
        for (var i = entries.length - 1; i >= 0; --i)
            _disposeEntry(entries[i], _cachePolicy(entries[i].route, entries[i].requestedCache));
        if (backgroundItem) {
            backgroundItem.transitionX = 0;
            backgroundItem.opacity = 1;
            backgroundItem.visible = true;
        }
        qmlGlobal.currentPageIndex = YEnum.PageIndex.NonePage;
    }
}
