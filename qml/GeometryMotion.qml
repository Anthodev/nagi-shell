import QtQuick

// Two analytically integrated, critically damped
// dimensions, sharing one frame clock. The caller owns requests and face lifetime.
Item {
    id: motion
    visible: false

    property real renderedWidth: 1
    property real renderedHeight: 1
    property real widthVelocity: 0
    property real heightVelocity: 0
    property real widthTarget: 1
    property real heightTarget: 1
    property real widthUpper: 1
    property real heightUpper: 1
    property real pixelEpsilon: 0.5
    property real omega: 40
    property bool initialized: false
    property bool running: false
    property bool freshStart: true
    property bool pending: false
    property real pendingWidth: 1
    property real pendingHeight: 1

    signal settled
    signal targetWillChange(real nextWidth, real nextHeight)

    FrameAnimation {
        running: motion.running
        onTriggered: motion.advance(frameTime)
    }

    function clamp(value, upper) {
        return Math.max(1, Math.min(upper, value));
    }
    function epsilon() {
        return Math.max(0.000001, pixelEpsilon / 2);
    }
    function axisSettled(position, velocity, target) {
        return Math.abs(position - target) <= epsilon() && Math.abs(velocity) / omega <= epsilon();
    }
    function project() {
        const width = clamp(renderedWidth, widthUpper);
        if (width !== renderedWidth) {
            renderedWidth = width;
            if ((width === 1 && widthVelocity < 0) || (width === widthUpper && widthVelocity > 0))
                widthVelocity = 0;
        }
        const height = clamp(renderedHeight, heightUpper);
        if (height !== renderedHeight) {
            renderedHeight = height;
            if ((height === 1 && heightVelocity < 0) || (height === heightUpper && heightVelocity
                                                         > 0))
                heightVelocity = 0;
        }
    }
    function refreshRunning() {
        if (axisSettled(renderedWidth, widthVelocity, widthTarget)) {
            renderedWidth = widthTarget;
            widthVelocity = 0;
        }
        if (axisSettled(renderedHeight, heightVelocity, heightTarget)) {
            renderedHeight = heightTarget;
            heightVelocity = 0;
        }
        const next = pending || !axisSettled(renderedWidth, widthVelocity, widthTarget) ||
              !axisSettled(renderedHeight, heightVelocity, heightTarget);
        const previous = running;
        if (next && !previous)
            freshStart = true;
        running = next;
        if (previous && !next)
            settled();
    }
    function initialize(width, height, maxWidth, maxHeight, physicalPixel) {
        widthUpper = Math.max(1, maxWidth);
        heightUpper = Math.max(1, maxHeight);
        pixelEpsilon = Math.max(0.000001, physicalPixel);
        renderedWidth = widthTarget = clamp(width, widthUpper);
        renderedHeight = heightTarget = clamp(height, heightUpper);
        widthVelocity = heightVelocity = 0;
        running = pending = false;
        freshStart = true;
        initialized = true;
    }
    function setBounds(maxWidth, maxHeight, physicalPixel) {
        if (!initialized)
            return;
        widthUpper = Math.max(1, maxWidth);
        heightUpper = Math.max(1, maxHeight);
        pixelEpsilon = Math.max(0.000001, physicalPixel);
        widthTarget = clamp(widthTarget, widthUpper);
        heightTarget = clamp(heightTarget, heightUpper);
        if (pending) {
            pendingWidth = clamp(pendingWidth, widthUpper);
            pendingHeight = clamp(pendingHeight, heightUpper);
        }
        project();
        refreshRunning();
    }
    function setMotionScale(scale) {
        if (!initialized)
            return;
        if (scale <= 0) {
            snap(pending ? pendingWidth : widthTarget, pending ? pendingHeight : heightTarget);
            return;
        }
        omega = 40 / scale;
        refreshRunning();
    }
    function applyTarget(width, height) {
        const nextWidth = clamp(width, widthUpper);
        const nextHeight = clamp(height, heightUpper);
        if (nextWidth === widthTarget && nextHeight === heightTarget)
            return;
        targetWillChange(nextWidth, nextHeight);
        widthTarget = nextWidth;
        heightTarget = nextHeight;
        refreshRunning();
    }
    function requestTarget(width, height) {
        if (!initialized)
            return;
        if (running) {
            pendingWidth = width;
            pendingHeight = height;
            pending = true;
        } else {
            applyTarget(width, height);
        }
    }
    function advance(frameTime) {
        if (!initialized || !running)
            return;
        // A newly awakened FrameAnimation has no reliable previous active frame.
        // A running predecessor does: advance it before retargeting, preserving x/v.
        const dt = freshStart ? 0 : Math.max(0, frameTime);
        freshStart = false;
        if (dt > 0) {
            let y = renderedWidth - widthTarget;
            let b = widthVelocity + omega * y;
            let e = Math.exp(-omega * dt);
            renderedWidth = widthTarget + (y + b * dt) * e;
            widthVelocity = (widthVelocity - omega * b * dt) * e;
            y = renderedHeight - heightTarget;
            b = heightVelocity + omega * y;
            e = Math.exp(-omega * dt);
            renderedHeight = heightTarget + (y + b * dt) * e;
            heightVelocity = (heightVelocity - omega * b * dt) * e;
            project();
        }
        if (pending) {
            const w = pendingWidth;
            const h = pendingHeight;
            pending = false;
            applyTarget(w, h);
        }
        refreshRunning();
    }
    function snap(width, height) {
        if (!initialized)
            return;
        pending = false;
        widthTarget = renderedWidth = clamp(width, widthUpper);
        heightTarget = renderedHeight = clamp(height, heightUpper);
        widthVelocity = heightVelocity = 0;
        refreshRunning();
    }
    function stop() {
        pending = false;
        running = false;
        freshStart = true;
    }
}
