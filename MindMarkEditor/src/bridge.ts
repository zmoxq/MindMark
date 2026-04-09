/**
 * MindMark Bridge — Dual Format + Image Upload/Download/Resolve
 *
 * Image flows:
 *   Upload (local file):  JS base64 → Swift saves → returns relative path
 *   Download (http URL):  JS sends URL → Swift downloads & saves → returns relative path
 *   Resolve (display):    JS sends relative path → Swift reads file → returns data URL
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

// ─── Promise-based request handling ──────────────────────────────────

let requestCounter = 0;
const pendingRequests = new Map<
  string,
  { resolve: (value: string) => void; reject: (err: Error) => void }
>();

// Upload response
onSwiftMessage("imageUploaded", (payload: unknown) => {
  const { requestId, relativePath, error } = payload as {
    requestId: string;
    relativePath?: string;
    error?: string;
  };
  const pending = pendingRequests.get(requestId);
  if (!pending) return;
  pendingRequests.delete(requestId);
  if (error || !relativePath) {
    pending.reject(new Error(error || "Upload failed"));
  } else {
    pending.resolve(relativePath);
  }
});

// Download response
onSwiftMessage("imageDownloaded", (payload: unknown) => {
  const { requestId, relativePath, error } = payload as {
    requestId: string;
    relativePath?: string;
    error?: string;
  };
  const pending = pendingRequests.get(requestId);
  if (!pending) return;
  pendingRequests.delete(requestId);
  if (error || !relativePath) {
    pending.reject(new Error(error || "Download failed"));
  } else {
    pending.resolve(relativePath);
  }
});

// Resolve response
onSwiftMessage("imageResolved", (payload: unknown) => {
  const { requestId, dataURL } = payload as {
    requestId: string;
    dataURL?: string;
  };
  const pending = pendingRequests.get(requestId);
  if (!pending) return;
  pendingRequests.delete(requestId);
  if (dataURL) {
    pending.resolve(dataURL);
  } else {
    pending.reject(new Error("Image resolution failed"));
  }
});

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

  /** Upload local image (base64) → returns relative path */
  uploadImage(base64Data: string, fileName: string): Promise<string> {
    const requestId = `upload_${++requestCounter}_${Date.now()}`;
    return new Promise((resolve, reject) => {
      pendingRequests.set(requestId, { resolve, reject });
      postToSwift("uploadImage", { requestId, base64Data, fileName });
      setTimeout(() => {
        if (pendingRequests.has(requestId)) {
          pendingRequests.delete(requestId);
          reject(new Error("Image upload timed out"));
        }
      }, 30000);
    });
  },

  /** Download remote image (http URL) → Swift downloads & saves → returns relative path */
  downloadImage(url: string): Promise<string> {
    const requestId = `download_${++requestCounter}_${Date.now()}`;
    return new Promise((resolve, reject) => {
      pendingRequests.set(requestId, { resolve, reject });
      postToSwift("downloadImage", { requestId, url });
      setTimeout(() => {
        if (pendingRequests.has(requestId)) {
          pendingRequests.delete(requestId);
          reject(new Error("Image download timed out"));
        }
      }, 60000); // 60s timeout for network downloads
    });
  },

  /** Resolve relative path → data URL for display */
  resolveImage(url: string): Promise<string> {
    const requestId = `resolve_${++requestCounter}_${Date.now()}`;
    return new Promise((resolve, reject) => {
      pendingRequests.set(requestId, { resolve, reject });
      postToSwift("resolveImage", { requestId, url });
      setTimeout(() => {
        if (pendingRequests.has(requestId)) {
          pendingRequests.delete(requestId);
          reject(new Error("Image resolve timed out"));
        }
      }, 10000);
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
