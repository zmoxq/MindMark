import type { Mark } from "prosemirror-model";
import type { EditorView, MarkView, ViewMutationRecord } from "prosemirror-view";
import type { BlockNoteEditor } from "@blocknote/core";
import type { CoreMarkViewSpec, CoreMarkViewUserOptions, MarkViewDOMSpec } from "./CoreMarkViewOptions.js";
export declare class CoreMarkView<ComponentType> implements MarkView {
    #private;
    dom: HTMLElement;
    contentDOM: HTMLElement | undefined;
    mark: Mark;
    view: EditorView;
    inline: boolean;
    options: CoreMarkViewUserOptions<ComponentType>;
    editor: BlockNoteEditor<any, any, any>;
    createDOM(as?: MarkViewDOMSpec): HTMLElement;
    createContentDOM(as?: MarkViewDOMSpec): HTMLElement;
    constructor({ mark, view, inline, options, editor, }: CoreMarkViewSpec<ComponentType>);
    get component(): ComponentType;
    shouldIgnoreMutation: (mutation: ViewMutationRecord) => boolean;
    ignoreMutation: (mutation: ViewMutationRecord) => boolean;
    destroy(): void;
}
