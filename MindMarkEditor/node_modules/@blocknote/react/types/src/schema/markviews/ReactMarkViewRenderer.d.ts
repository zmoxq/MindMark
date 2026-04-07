import { CoreMarkView } from "./CoreMarkView.js";
import type { MarkViewContext } from "./markViewContext.js";
import type { ReactMarkViewComponent } from "./ReactMarkViewOptions.js";
export declare class ReactMarkView extends CoreMarkView<ReactMarkViewComponent> {
    id: string;
    context: MarkViewContext;
    updateContext: () => void;
    render: () => void;
    destroy: () => void;
    renderer: () => {
        reactElement: import("react/jsx-runtime").JSX.Element;
        element: HTMLElement;
    };
}
