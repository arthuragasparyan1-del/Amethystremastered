
// Left and right Shift are tracked independently using atomic state.
// This allows keyboard and mouse callbacks on different threads
// to read and update the Shift state safely.

static atomic_bool leftShiftDown = ATOMIC_VAR_INIT(false);
static atomic_bool rightShiftDown = ATOMIC_VAR_INIT(false);

static inline char currentShiftModifier(void) {
    BOOL left = atomic_load_explicit(
        &leftShiftDown,
        memory_order_acquire
    );

    BOOL right = atomic_load_explicit(
        &rightShiftDown,
        memory_order_acquire
    );

    return (left || right) ? GLFW_MOD_SHIFT : 0;
}

static void updateShiftState(int key, int action) {
    BOOL down = action != 0;

    if (key == GLFW_KEY_LEFT_SHIFT) {
        atomic_store_explicit(
            &leftShiftDown,
            down,
            memory_order_release
        );
    } else if (key == GLFW_KEY_RIGHT_SHIFT) {
        atomic_store_explicit(
            &rightShiftDown,
            down,
            memory_order_release
        );
    }
}

char getKeyModifiers(int key, int action) {
    static char currMods;

    char mod;

    switch (key) {
        case GLFW_KEY_LEFT_CONTROL:
            mod = GLFW_MOD_CONTROL;
            break;

        case GLFW_KEY_LEFT_ALT:
            mod = GLFW_MOD_ALT;
            break;

        case GLFW_KEY_CAPS_LOCK:
            mod = GLFW_MOD_CAPS_LOCK;
            break;

        case GLFW_KEY_NUM_LOCK:
            mod = GLFW_MOD_NUM_LOCK;
            break;

        default:
            return (currMods & ~GLFW_MOD_SHIFT)
                | currentShiftModifier();
    }

    if (action) {
        currMods |= mod;
    } else {
        currMods &= ~mod;
    }

    return (currMods & ~GLFW_MOD_SHIFT)
        | currentShiftModifier();
}

void CallbackBridge_nativeSendKey(
    int key,
    int scancode,
    int action,
    int mods
) {
    updateShiftState(key, action);

    char tracked = getKeyModifiers(key, action);

    if (GLFW_invoke_Key && isInputReady) {
        keyDownBuffer[MAX(0, key - 31)] = (jbyte)action;

        if (mods == 0) {
            mods = tracked;
        } else {
            mods |= currentShiftModifier();
        }

        if (
            (key == GLFW_KEY_LEFT_SHIFT ||
             key == GLFW_KEY_RIGHT_SHIFT) &&
            action == 0 &&
            !currentShiftModifier()
        ) {
            mods &= ~GLFW_MOD_SHIFT;
        }

        if (isUseStackQueueCall) {
            sendData(
                EVENT_TYPE_KEY,
                key,
                scancode,
                action,
                mods
            );
        } else {
            GLFW_invoke_Key(
                (void*)showingWindow,
                key,
                scancode,
                action,
                mods
            );
        }
    }

    if (key == GLFW_KEY_LEFT_CONTROL) {
        CallbackBridge_nativeSendKey(
            GLFW_KEY_LEFT_SUPER,
            0,
            action,
            mods
        );
    } else if (key == GLFW_KEY_RIGHT_CONTROL) {
        CallbackBridge_nativeSendKey(
            GLFW_KEY_RIGHT_SUPER,
            0,
            action,
            mods
        );
    }
}

void CallbackBridge_nativeSendMouseButton(
    int button,
    int action,
    int mods
) {
    if (!isInputReady) {
        return;
    }

    if (button == -1 || !GLFW_invoke_MouseButton) {
        return;
    }

    if (mods == 0) {
        mods = getKeyModifiers(0, action);
    }

    // Preserve Shift when a mouse click occurs while Shift is held.
    mods |= currentShiftModifier();

    if (isUseStackQueueCall) {
        sendData(
            EVENT_TYPE_MOUSE_BUTTON,
            button,
            action,
            mods,
            0
        );
    } else {
        GLFW_invoke_MouseButton(
            (void*)showingWindow,
            button,
            action,
            mods
        );
    }
}
