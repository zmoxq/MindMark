/**
 * MindMark Bridge — Dual Format + Image Upload
 *
 * Swift → JS: window.mindmark.receiveFromSwift(action, payload)
 * JS → Swift: window.webkit.messageHandlers.mindmark.postMessage({action, payload})
 *
 * Image upload flow:
 *   1. JS calls bridge.uploadImage(base64, fileName) → returns Promise<string>
 *   2. Swift saves file to attachment folder
 *   3. Swift calls receiveFromSwift('imageUploaded', {requestId, relativePath})
 *   4. Promise resolves with the relative path
 */

export interface BridgeMessage {
  action: string;
  payload: unknown;
}

// ─── Swift → JS ──────────────────────────────────────────────────────

type MessageHandler = (payload: unknown) => void;
const handlers = new Map<string, MessageHandler>();

export function onSwiftMessage(action: string, handler: MessageHandler) {
  handlers.set(action, handler);
}

function receiveFromSwift(action: string, payload: unknown) {
  const handler = handlers.get(action);
  if (handler) {
    handler(payload);
  } else {
    console.warn(`[Bridge] No handler for action: ${action}`);
  }
}

// ─── JS → Swift ──────────────────────────────────────────────────────

function postToSwift(action: string, payload: unknown = null) {
  try {
    const w = window as unknown as {
      webkit?: {
        messageHandlers?: {
          mindmark?: { postMessage: (msg: BridgeMessage) => void };
        };
      };
    };
    if (w.webkit?.messageHandlers?.mindmark) {
      w.webkit.messageHandlers.mindmark.postMessage({ action, payload });
    } else {
      console.log(`[Bridge → Swift] ${action}:`, payload);
    }
  } catch (e) {
    console.error("[Bridge] Failed to post to Swift:", e);
  }
}

// ─── Image Upload (Promise-based) ────────────────────────────────────

let uploadCounter = 0;
const pendingUploads = new Map<
  string,
  { resolve: (url: string) => void; reject: (err: Error) => void }
>();

// Listen for Swift's response to image uploads
onSwiftMessage(
  "imageUploaded",
  (payload: unknown) => {
    const { requestId, relativePath, error } = payload as {
      requestId: string;
      relativePath?: string;
      error?: string;
    };
    const pending = pendingUploads.get(requestId);
    if (!pending) return;
    pendingUploads.delete(requestId);

    if (error || !relativePath) {
      pending.reject(new Error(error || "Upload failed"));
    } else {
      pending.resolve(relativePath);
    }
  }
);

// ─── Public API ──────────────────────────────────────────────────────

export const bridge = {
  editorReady() {
    postToSwift("editorReady");
  },

  contentChanged(markdown: string, blocksJson: string) {
    postToSwift("contentChanged", { markdown, blocksJson });
  },

  requestSave(markdown: string, blocksJson: string) {
    postToSwift("requestSave", { markdown, blocksJson });
  },

  focusChanged(isFocused: boolean) {
    postToSwift("focusChanged", { isFocused });
  },

  /**
   * Upload an image to Swift for saving in the attachment folder.
   * Returns a Promise that resolves with the relative path to use in markdown.
   */
  uploadImage(base64Data: string, fileName: string): Promise<string> {
    const requestId = `img_${++uploadCounter}_${Date.now()}`;

    return new Promise((resolve, reject) => {
      pendingUploads.set(requestId, { resolve, reject });

      postToSwift("uploadImage", {
        requestId,
        base64Data,
        fileName,
      });

      // Timeout after 30 seconds
      setTimeout(() => {
        if (pendingUploads.has(requestId)) {
          pendingUploads.delete(requestId);
          reject(new Error("Image upload timed out"));
        }
      }, 30000);
    });
  },

  log(message: string) {
    postToSwift("log", { message });
  },
};

// ─── Global receiver ─────────────────────────────────────────────────

declare global {
  interface Window {
    mindmark: { receiveFromSwift: typeof receiveFromSwift };
  }
}

window.mindmark = { receiveFromSwift };
