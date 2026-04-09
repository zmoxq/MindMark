import { useEffect, useCallback, useRef } from "react";
import { useCreateBlockNote } from "@blocknote/react";
import { BlockNoteView } from "@blocknote/mantine";
import { Block } from "@blocknote/core";

import "@blocknote/core/fonts/inter.css";
import "@blocknote/mantine/style.css";

import { bridge, onSwiftMessage } from "./bridge";

// ─── Debounce utility ────────────────────────────────────────────────

function useDebouncedCallback<T extends (...args: unknown[]) => void>(
  callback: T,
  delay: number
): T {
  const timeoutRef = useRef<ReturnType<typeof setTimeout>>();
  return useCallback(
    ((...args: unknown[]) => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
      timeoutRef.current = setTimeout(() => callback(...args), delay);
    }) as T,
    [callback, delay]
  );
}

// ─── File → Base64 helper ────────────────────────────────────────────

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      const base64 = result.split(",")[1] || result;
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

// ─── Blob URL → Base64 helper ────────────────────────────────────────

async function blobUrlToBase64(blobUrl: string): Promise<{
  base64: string;
  mimeType: string;
}> {
  const response = await fetch(blobUrl);
  const blob = await response.blob();
  const mimeType = blob.type || "image/png";
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      const base64 = result.split(",")[1] || result;
      resolve({ base64, mimeType });
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

function mimeToExtension(mimeType: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/svg+xml": "svg",
  };
  return map[mimeType] || "png";
}

// ─── Theme injection ─────────────────────────────────────────────────

const THEME_STYLE_ID = "mindmark-theme";

function applyThemeCSS(css: string) {
  let styleEl = document.getElementById(THEME_STYLE_ID) as HTMLStyleElement;
  if (!styleEl) {
    styleEl = document.createElement("style");
    styleEl.id = THEME_STYLE_ID;
    document.head.appendChild(styleEl);
  }
  styleEl.textContent = css;
  bridge.log(`Theme applied (${css.length} bytes)`);
}

function clearTheme() {
  const styleEl = document.getElementById(THEME_STYLE_ID);
  if (styleEl) styleEl.textContent = "";
  bridge.log("Theme cleared (using default)");
}

// ─── Upload handler (for /image → Upload) ────────────────────────────

async function uploadFile(file: File): Promise<string> {
  try {
    const base64 = await fileToBase64(file);
    const fileName = file.name || `image-${Date.now()}.png`;
    bridge.log(
      `Uploading image: ${fileName} (${Math.round(base64.length / 1024)}KB)`
    );
    const relativePath = await bridge.uploadImage(base64, fileName);
    bridge.log(`Image saved: ${relativePath}`);
    return relativePath;
  } catch (e) {
    bridge.log(`Image upload failed: ${e}`);
    throw e;
  }
}

// ─── Resolve handler (for displaying images) ─────────────────────────

async function resolveFileUrl(url: string): Promise<string> {
  if (url.startsWith("data:") || url.startsWith("blob:")) {
    return url;
  }
  // http URLs will be downloaded by processRemoteImages, so just pass through
  if (url.startsWith("http")) {
    return url;
  }
  // Relative path → ask Swift to read file and return data URL
  try {
    const dataURL = await bridge.resolveImage(url);
    return dataURL;
  } catch (e) {
    bridge.log(`Failed to resolve image: ${url} — ${e}`);
    return url;
  }
}

// ─── Editor Component ────────────────────────────────────────────────

export default function Editor() {
  const editor = useCreateBlockNote({
    uploadFile,
    resolveFileUrl,
    domAttributes: {
      editor: { class: "mindmark-editor" },
    },
  });

  // Track URLs we've already processed
  const processedUrls = useRef<Set<string>>(new Set());

  // ─── Scan and process non-local image URLs ─────────────────────

  const processImages = useCallback(async () => {
    if (!editor) return;
    for (const block of editor.document) {
      await scanBlock(block);
    }

    async function scanBlock(block: Block) {
      if (
        block.type === "image" &&
        block.props &&
        typeof (block.props as Record<string, unknown>).url === "string"
      ) {
        const url = (block.props as Record<string, unknown>).url as string;

        // Skip already processed, relative paths, and data URLs
        if (
          processedUrls.current.has(url) ||
          url.startsWith("./") ||
          url.startsWith("data:") ||
          url === ""
        ) {
          return;
        }

        processedUrls.current.add(url);

        // Handle blob: URLs (from paste)
        if (url.startsWith("blob:")) {
          bridge.log(`Found blob image, uploading...`);
          try {
            const { base64, mimeType } = await blobUrlToBase64(url);
            const ext = mimeToExtension(mimeType);
            const fileName = `pasted-${Date.now()}.${ext}`;
            const relativePath = await bridge.uploadImage(base64, fileName);
            bridge.log(`Pasted image saved: ${relativePath}`);
            editor.updateBlock(block.id, { props: { url: relativePath } });
          } catch (e) {
            bridge.log(`Failed to process blob image: ${e}`);
          }
          return;
        }

        // Handle http/https URLs (from embed)
        if (url.startsWith("http://") || url.startsWith("https://")) {
          bridge.log(`Found remote image, downloading: ${url.substring(0, 80)}...`);
          try {
            const relativePath = await bridge.downloadImage(url);
            bridge.log(`Remote image downloaded: ${relativePath}`);
            editor.updateBlock(block.id, { props: { url: relativePath } });
          } catch (e) {
            bridge.log(`Failed to download remote image: ${e}`);
            // Keep the http URL as fallback
          }
          return;
        }
      }

      if (block.children) {
        for (const child of block.children) {
          await scanBlock(child);
        }
      }
    }
  }, [editor]);

  // ─── Dual-format save ──────────────────────────────────────────

  const sendDualContent = useCallback(async () => {
    if (!editor) return;
    try {
      const markdown = await editor.blocksToMarkdownLossy(editor.document);
      const blocksJson = JSON.stringify(editor.document);
      bridge.contentChanged(markdown, blocksJson);
    } catch (e) {
      bridge.log(`Error converting content: ${e}`);
    }
  }, [editor]);

  const debouncedSave = useDebouncedCallback(sendDualContent, 500);

  useEffect(() => {
    if (!editor) return;
    editor.onChange(() => {
      processImages();
      debouncedSave();
    });
  }, [editor, debouncedSave, processImages]);

  // ─── Handle messages from Swift ──────────────────────────────────

  useEffect(() => {
    onSwiftMessage("loadDocument", async (payload) => {
      const data = payload as { markdown?: string; blocksJson?: string };
      try {
        processedUrls.current.clear();
        if (data.blocksJson) {
          const blocks = JSON.parse(data.blocksJson) as Block[];
          editor.replaceBlocks(editor.document, blocks);
          bridge.log("Document loaded from JSON (lossless)");
        } else if (data.markdown) {
          const blocks = await editor.tryParseMarkdownToBlocks(data.markdown);
          editor.replaceBlocks(editor.document, blocks);
          bridge.log("Document loaded from Markdown (lossy)");
        }
      } catch (e) {
        bridge.log(`Error loading document: ${e}`);
      }
    });

    onSwiftMessage("getContent", async () => {
      try {
        const markdown = await editor.blocksToMarkdownLossy(editor.document);
        const blocksJson = JSON.stringify(editor.document);
        bridge.requestSave(markdown, blocksJson);
      } catch (e) {
        bridge.log(`Error getting content: ${e}`);
      }
    });

    onSwiftMessage("newDocument", () => {
      editor.replaceBlocks(editor.document, []);
      processedUrls.current.clear();
      bridge.log("New document created");
    });

    onSwiftMessage("applyTheme", (payload) => {
      const { css } = payload as { css: string };
      if (css && css.length > 0) {
        applyThemeCSS(css);
      } else {
        clearTheme();
      }
    });

    bridge.editorReady();
  }, [editor]);

  return (
    <div style={{ height: "100vh", overflow: "auto" }}>
      <BlockNoteView editor={editor} theme="light" />
    </div>
  );
}
