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

// ─── Extension helper ────────────────────────────────────────────────

function mimeToExtension(mimeType: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/svg+xml": "svg",
    "image/tiff": "tiff",
  };
  return map[mimeType] || "png";
}

// ─── Upload handler (for /image → Upload file dialog) ────────────────

async function uploadFile(file: File): Promise<string> {
  try {
    const base64 = await fileToBase64(file);
    const fileName = file.name || `image-${Date.now()}.png`;
    bridge.log(`Uploading image: ${fileName} (${Math.round(base64.length / 1024)}KB)`);

    const dataUrl = await bridge.uploadImage(base64, fileName);
    bridge.log(`Image saved: ${fileName}`);
    return dataUrl;
  } catch (e) {
    bridge.log(`Image upload failed: ${e}`);
    throw e;
  }
}

// ─── Editor Component ────────────────────────────────────────────────

export default function Editor() {
  const editor = useCreateBlockNote({
    uploadFile,
    domAttributes: {
      editor: { class: "mindmark-editor" },
    },
  });

  // Track blob URLs we've already processed to avoid duplicates
  const processedBlobUrls = useRef<Set<string>>(new Set());

  // ─── Scan for blob URLs and upload them ────────────────────────

  const processBlobImages = useCallback(async () => {
    if (!editor) return;

    // Walk through all blocks looking for image blocks with blob: URLs
    const blocks = editor.document;

    for (const block of blocks) {
      await scanAndUploadBlobs(block);
    }

    async function scanAndUploadBlobs(block: Block) {
      if (
        block.type === "image" &&
        block.props &&
        typeof (block.props as Record<string, unknown>).url === "string"
      ) {
        const url = (block.props as Record<string, unknown>).url as string;

        // Check if it's a blob URL that we haven't processed yet
        if (url.startsWith("blob:") && !processedBlobUrls.current.has(url)) {
          processedBlobUrls.current.add(url);
          bridge.log(`Found blob image, uploading: ${url.substring(0, 50)}...`);

          try {
            const { base64, mimeType } = await blobUrlToBase64(url);
            const ext = mimeToExtension(mimeType);
            const fileName = `pasted-${Date.now()}.${ext}`;

            const dataUrl = await bridge.uploadImage(base64, fileName);
            bridge.log(`Pasted image saved: ${fileName}`);

            // Update the block's URL from blob: to data: URL
            editor.updateBlock(block.id, {
              props: { url: dataUrl },
            });
          } catch (e) {
            bridge.log(`Failed to process pasted image: ${e}`);
          }
        }
      }

      // Recurse into children
      if (block.children) {
        for (const child of block.children) {
          await scanAndUploadBlobs(child);
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
      // Check for blob images on every change
      processBlobImages();
      debouncedSave();
    });
  }, [editor, debouncedSave, processBlobImages]);

  // ─── Handle messages from Swift ──────────────────────────────────

  useEffect(() => {
    onSwiftMessage("loadDocument", async (payload) => {
      const data = payload as { markdown?: string; blocksJson?: string };
      try {
        // Clear processed blob cache on new document
        processedBlobUrls.current.clear();

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
      processedBlobUrls.current.clear();
      bridge.log("New document created");
    });

    bridge.editorReady();
  }, [editor]);

  // ─── Render ──────────────────────────────────────────────────────

  return (
    <div style={{ height: "100vh", overflow: "auto" }}>
      <BlockNoteView editor={editor} theme="light" />
    </div>
  );
}
