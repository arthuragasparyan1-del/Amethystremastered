
#include "utils.h"
#include "glfw_keycodes.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdlib.h>

// Track left and right Shift independently.
static atomic_bool leftShiftDown = ATOMIC_VAR_INIT(false);
static atomic_bool rightShiftDown = ATOMIC_VAR_INIT(false);

static inline char currentShiftModifier(void) {
    bool left = atomic_load_explicit(&leftShiftDown, memory_order_acquire);
    bool right = atomic_load_explicit(&rightShiftDown, memory_order_acquire);
    return (left || right) ? GLFW_MOD_SHIFT : 0;
}

static void updateShiftState(int key, int action) {
    bool down = (action != 0);

    if (key == GLFW_KEY_LEFT_SHIFT) {
        atomic_store_explicit(&leftShiftDown, down, memory_order_release);
    } else if (key == GLFW_KEY_RIGHT_SHIFT) {
        atomic_store_explicit(&rightShiftDown, down, memory_order_release);
    }
}

char getKeyModifiers(int key, int action) {
    static char currMods = 0;
    char mod;

    switch (key) {
        case GLFW_KEY_LEFT_CONTROL:
        case GLFW_KEY_RIGHT_CONTROL:
            mod = GLFW_MOD_CONTROL;
            break;

        case GLFW_KEY_LEFT_ALT:
        case GLFW_KEY_RIGHT_ALT:
            mod = GLFW_MOD_ALT;
            break;

        case GLFW_KEY_CAPS_LOCK:
            mod = GLFW_MOD_CAPS_LOCK;
            break;

        case GLFW_KEY_NUM_LOCK:
            mod = GLFW_MOD_NUM_LOCK;
            break;

        default:
            return (currMods & ~GLFW_MOD_SHIFT) | currentShiftModifier();
    }

    if (action != 0) {
        currMods |= mod;
    } else {
        currMods &= ~mod;
    }

    return (currMods & ~GLFW_MOD_SHIFT) | currentShiftModifier();
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
            currentShiftModifier() == 0
        ) {
            mods &= ~GLFW_MOD_SHIFT;
        }

        if (isUseStackQueueCall) {
            sendData(EVENT_TYPE_KEY, key, scancode, action, mods);
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
            GLFW_KEY_LEFT_SUPER, 0, action, mods
        );
    } else if (key == GLFW_KEY_RIGHT_CONTROL) {
        CallbackBridge_nativeSendKey(
            GLFW_KEY_RIGHT_SUPER, 0, action, mods
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

    // Preserve Shift when clicking while Shift is held.
    mods |= currentShiftModifier();

    if (isUseStackQueueCall) {
        sendData(EVENT_TYPE_MOUSE_BUTTON, button, action, mods, 0);
    } else {
        GLFW_invoke_MouseButton(
            (void*)showingWindow,
            button,
            action,
            mods
        );
    }
}

// Event queue functions.

void sendData(short type, int i1, int i2, short i3, short i4) {
    size_t counter = atomic_load_explicit(
        &eventCounter, memory_order_acquire
    );

    if (counter < 7999) {
        GLFWInputEvent *event = &events[counter++];
        event->type = type;
        event->i1 = i1;
        event->i2 = i2;
        event->i3 = i3;
        event->i4 = i4;
    }

    atomic_store_explicit(&eventCounter, counter, memory_order_release);
}

void sendDataFloat(short type, float i1, float i2, short i3, short i4) {
    size_t counter = atomic_load_explicit(
        &eventCounter, memory_order_acquire
    );

    if (counter < 7999) {
        GLFWInputEvent *event = &events[counter++];
        event->type = type;
        event->f1 = i1;
        event->f2 = i2;
        event->i3 = i3;
        event->i4 = i4;
    }

    atomic_store_explicit(&eventCounter, counter, memory_order_release);
}

// Hotbar support.

const int hotbarKeys[9] = {
    GLFW_KEY_1, GLFW_KEY_2, GLFW_KEY_3,
    GLFW_KEY_4, GLFW_KEY_5, GLFW_KEY_6,
    GLFW_KEY_7, GLFW_KEY_8, GLFW_KEY_9
};

int guiScale = 1;

int mcscale(CGFloat input) {
    return (int)((guiScale * input) / resolutionScale);
}

int callback_SurfaceViewController_touchHotbar(CGFloat x, CGFloat y) {
    if (isGrabbing == JNI_FALSE) {
        return -1;
    }

    int barHeight = mcscale(20);
    int barY = physicalHeight - barHeight;
    if (y < barY) return -1;

    int barWidth = mcscale(180);
    int barX = (physicalWidth / 2) - (barWidth / 2);
    if (x < barX || x >= barX + barWidth) return -1;

    return hotbarKeys[
        (int)MathUtils_map(x, barX, barX + barWidth, 0, 9)
    ];
}

// Called when the input system becomes ready.

void CallbackBridge_nativeSetInputReady(BOOL inputReady) {
    isInputReady = inputReady;

    if (inputReady) {
        if (GLFW_invoke_FramebufferSize) {
            GLFW_invoke_FramebufferSize(
                (void*)showingWindow, windowWidth, windowHeight
            );
        }

        if (GLFW_invoke_WindowSize) {
            GLFW_invoke_WindowSize(
                (void*)showingWindow, windowWidth, windowHeight
            );
        }
    }
}

// Character input.

BOOL CallbackBridge_nativeSendChar(jchar codepoint) {
    if (GLFW_invoke_Char && isInputReady) {
        if (isUseStackQueueCall) {
            sendData(EVENT_TYPE_CHAR, codepoint, 0, 0, 0);
        } else {
            GLFW_invoke_Char(
                (void*)showingWindow, (unsigned int)codepoint
            );
        }
        return YES;
    }

    return NO;
}

BOOL CallbackBridge_nativeSendCharMods(jchar codepoint, int mods) {
    if (GLFW_invoke_CharMods && isInputReady) {
        if (isUseStackQueueCall) {
            sendData(
                EVENT_TYPE_CHAR_MODS,
                (unsigned int)codepoint,
                mods,
                0,
                0
            );
        } else {
            GLFW_invoke_CharMods(
                (void*)showingWindow, codepoint, mods
            );
        }
        return YES;
    }

    return NO;
}

// Cursor input.

void CallbackBridge_nativeSendCursorPos(
    char event,
    CGFloat x,
    CGFloat y
) {
    if (!GLFW_invoke_CursorPos || !isInputReady) {
        return;
    }

    switch (event) {
        case ACTION_DOWN:
        case ACTION_UP:
            if (!isGrabbing) {
                cursorX = x;
                cursorY = y;
            }
            break;

        case ACTION_MOVE:
            if (isGrabbing) {
                cursorX += x - cLastX;
                cursorY += y - cLastY;
            } else {
                cursorX = x;
                cursorY = y;
            }
            break;

        case ACTION_MOVE_MOTION:
            cursorX += x;
            cursorY += y;
            break;
    }

    if (!isUseStackQueueCall) {
        GLFW_invoke_CursorPos(
            (void*)showingWindow,
            (double)cursorX,
            (double)cursorY
        );
    }
}

// Screen-size callbacks.

void CallbackBridge_nativeSendScreenSize(int width, int height) {
    windowWidth = width;
    windowHeight = height;

    if (isInputReady) {
        if (GLFW_invoke_FramebufferSize) {
            if (isUseStackQueueCall) {
                sendData(
                    EVENT_TYPE_FRAMEBUFFER_SIZE,
                    width, height, 0, 0
                );
            } else {
                GLFW_invoke_FramebufferSize(
                    (void*)showingWindow, width, height
                );
            }
        }

        if (GLFW_invoke_WindowSize) {
            if (isUseStackQueueCall) {
                sendData(
                    EVENT_TYPE_WINDOW_SIZE,
                    width, height, 0, 0
                );
            } else {
                GLFW_invoke_WindowSize(
                    (void*)showingWindow, width, height
                );
            }
        }
    }
}

// Scroll input.

void CallbackBridge_nativeSendScroll(
    CGFloat xoffset,
    CGFloat yoffset
) {
    if (GLFW_invoke_Scroll && isInputReady) {
        if (isUseStackQueueCall) {
            sendDataFloat(
                EVENT_TYPE_SCROLL, xoffset, yoffset, 0, 0
            );
        } else {
            GLFW_invoke_Scroll(
                (void*)showingWindow,
                (double)xoffset,
                (double)yoffset
            );
        }
    }
}

// GLFW window reference.

JNIEXPORT void JNICALL
Java_org_lwjgl_glfw_GLFW_nglfwSetShowingWindow(
    JNIEnv* env,
    jclass clazz,
    jlong window
) {
    showingWindow = (long)window;
}

// GUI scale callback.

JNIEXPORT void JNICALL
Java_net_kdt_pojavlaunch_uikit_UIKit_updateMCGuiScale(
    JNIEnv* env,
    jclass clazz,
    jint scale
) {
    guiScale = scale;
}

// Close GLFW window.

void closeGLFWWindow(void) {
    NSLog(@"Closing GLFW window");
    exit(-1);
}

// Pause handling.

void CallbackBridge_pauseGameIfNeed(void) {
    if (isGrabbing) {
        CallbackBridge_nativeSendKey(GLFW_KEY_ESCAPE, 0, 1, 0);
        CallbackBridge_nativeSendKey(GLFW_KEY_ESCAPE, 0, 0, 0);
    }
}
