import {
  List,
  ActionPanel,
  Action,
  Detail,
  Form,
  showHUD,
  showToast,
  Toast,
  Icon,
  closeMainWindow,
  Keyboard,
  useNavigation,
} from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { useState, useCallback, useRef } from "react";
import {
  discoverServer,
  fetchSessions,
  fetchRecentProjects,
  fetchProjectDirectory,
  dispatch as dispatchToOpenCode,
  abbreviateHome,
  timeAgo,
} from "./opencode";
import { gatherContext, buildPrompt, type ContextItem } from "./context";
import { learnFromEdit } from "./vocabulary";

/** Keyboard number keys for Cmd+1 through Cmd+9 */
const NUM_KEYS: Keyboard.KeyEquivalent[] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"];

interface DispatchTarget {
  label: string;
  icon: Icon;
  sessionId?: string;
  workDir?: string;
}

export default function DispatchCommand() {
  const [prompt, setPrompt] = useState("");
  const initialPromptRef = useRef<string | null>(null);
  const [toggledItems, setToggledItems] = useState<Record<string, boolean>>({});
  const [extraFiles, setExtraFiles] = useState<string[]>([]);

  const { data, isLoading, error } = usePromise(async () => {
    const server = discoverServer();
    if (!server) throw new Error("not_found");

    const [sessions, recentProjects, projectDir, contextItems] = await Promise.all([
      fetchSessions(server),
      fetchRecentProjects(server),
      fetchProjectDirectory(server),
      gatherContext(),
    ]);

    return { server, sessions, recentProjects, projectDir, contextItems };
  });

  const contextItems = data?.contextItems ?? [];
  // Merge auto-detected context with manually attached files
  const allContextItems: ContextItem[] = [
    ...contextItems,
    ...extraFiles.map((f): ContextItem => ({
      type: "screenshot",
      label: f.split("/").pop() || f,
      value: f,
      defaultEnabled: true,
    })),
  ];

  const sessions = (data?.sessions ?? []).filter((s) => s.directory && s.directory !== "/");
  const projectDir = data?.projectDir;
  const recentProjects = data?.recentProjects ?? [];
  const defaultWorkDir = projectDir || recentProjects[0] || sessions[0]?.directory;
  const workspaceDirs = mergeWorkspaces(recentProjects, sessions);

  // Build ordered dispatch targets
  const targets: DispatchTarget[] = [];
  if (defaultWorkDir) {
    targets.push({
      label: `New session in ${abbreviateHome(defaultWorkDir)}`,
      icon: Icon.Plus,
      workDir: defaultWorkDir,
    });
  }
  for (const s of sessions) {
    targets.push({
      label: `${s.name} · ${timeAgo(s.updatedAt)}`,
      icon: Icon.Message,
      sessionId: s.id,
    });
  }
  for (const dir of workspaceDirs) {
    if (dir !== defaultWorkDir) {
      targets.push({
        label: `New session in ${abbreviateHome(dir)}`,
        icon: Icon.Plus,
        workDir: dir,
      });
    }
  }

  function isItemEnabled(item: ContextItem, index: number): boolean {
    const key = contextKey(item, index);
    return key in toggledItems ? toggledItems[key] : item.defaultEnabled;
  }

  const enabledCount = allContextItems.filter((item, i) => isItemEnabled(item, i)).length;

  const doDispatch = useCallback(
    async (sessionId: string | undefined, workDirOverride?: string) => {
      if (!data) return;

      const text = prompt.trim();
      if (!text) {
        await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
        return;
      }

      const activeContext = allContextItems.filter((item, i) => isItemEnabled(item, i));
      const fullPrompt = buildPrompt(text, activeContext);
      const filePaths = activeContext.filter((c) => c.type === "screenshot").map((c) => c.value);

      const workingDirectory = workDirOverride || defaultWorkDir;
      const dest = abbreviateHome(workingDirectory || "~");

      await closeMainWindow({ clearRootSearch: true });
      await showHUD(`Dispatched to ${dest}`);

      dispatchToOpenCode({
        prompt: fullPrompt,
        server: data.server,
        sessionId,
        filePaths,
        workingDirectory,
      }).then(async (result) => {
        if (result.success) {
          const original = initialPromptRef.current;
          if (original && original !== text) {
            learnFromEdit(original, text, data.server).catch(() => {});
          }
        }
      });
    },
    [data, prompt, allContextItems, toggledItems, defaultWorkDir],
  );

  function dispatchTarget(t: DispatchTarget) {
    doDispatch(t.sessionId, t.workDir);
  }

  if (error) {
    return (
      <Detail
        markdown={
          "## OpenCode Desktop Not Found\n\n" +
          "Aside requires OpenCode Desktop to be running.\n\n" +
          "Start OpenCode Desktop and try again."
        }
        actions={
          <ActionPanel>
            <Action.OpenInBrowser title="Get OpenCode Desktop" url="https://opencode.ai" />
          </ActionPanel>
        }
      />
    );
  }

  /** Dispatch target actions with Cmd+1-9 shortcuts */
  function dispatchActions() {
    return (
      <ActionPanel.Section title="Send to…">
        {targets.map((t, idx) => (
          <Action
            key={`target-${idx}`}
            title={t.label}
            icon={t.icon}
            shortcut={idx < NUM_KEYS.length ? { modifiers: ["cmd"], key: NUM_KEYS[idx] } : undefined}
            onAction={() => dispatchTarget(t)}
          />
        ))}
      </ActionPanel.Section>
    );
  }

  const contextSummary = allContextItems.length === 0
    ? "No context"
    : `${enabledCount} of ${allContextItems.length} items attached`;

  // Build hint string for placeholder
  const hint = targets.length > 0
    ? `⌘1 ${targets[0].label.split(" in ").pop() || "send"}`
    : "";

  return (
    <List
      isLoading={isLoading}
      searchBarPlaceholder={`Prompt…  ${hint}`}
      onSearchTextChange={(text) => {
        setPrompt(text);
        if (initialPromptRef.current === null && text.trim().length > 0) {
          initialPromptRef.current = text;
        }
      }}
      filtering={false}
    >
      {/* Context summary — pushes to detail view */}
      <List.Section title="Context">
        <List.Item
          icon={Icon.Paperclip}
          title={contextSummary}
          accessories={allContextItems.slice(0, 4).map((item) => ({
            icon: contextListIcon(item),
            tooltip: item.label,
          }))}
          actions={
            <ActionPanel>
              <Action.Push
                title="Manage Context"
                icon={Icon.Pencil}
                target={
                  <ContextEditor
                    items={allContextItems}
                    toggledItems={toggledItems}
                    onSetToggles={(toggles) => setToggledItems(toggles)}
                    onAddFiles={(files) => setExtraFiles((prev) => [...prev, ...files])}
                    dispatchActions={dispatchActions}
                  />
                }
              />
              {dispatchActions()}
            </ActionPanel>
          }
        />
      </List.Section>

      {/* Dispatch targets */}
      <List.Section title="Send to…">
        {targets.map((t, idx) => (
          <List.Item
            key={`target-${idx}`}
            icon={t.icon}
            title={t.label}
            accessories={idx < NUM_KEYS.length ? [{ tag: `⌘${NUM_KEYS[idx]}` }] : []}
            actions={
              <ActionPanel>
                <Action
                  title={t.label}
                  icon={t.icon}
                  onAction={() => dispatchTarget(t)}
                />
                {dispatchActions()}
              </ActionPanel>
            }
          />
        ))}
      </List.Section>

      {targets.length === 0 && allContextItems.length === 0 && (
        <List.EmptyView
          title="No context or sessions"
          description="Type a prompt and press ⌘1 to send"
        />
      )}
    </List>
  );
}

/** Form-based context editor with file picker and checkboxes */
function ContextEditor(props: {
  items: ContextItem[];
  toggledItems: Record<string, boolean>;
  onSetToggles: (toggles: Record<string, boolean>) => void;
  onAddFiles: (files: string[]) => void;
  dispatchActions: () => JSX.Element;
}) {
  const { pop } = useNavigation();

  function defaultEnabled(item: ContextItem, index: number): boolean {
    const key = contextKey(item, index);
    return key in props.toggledItems ? props.toggledItems[key] : item.defaultEnabled;
  }

  /** Read all checkbox values from form and sync back to parent */
  function syncToggles(values: Record<string, unknown>) {
    const toggles: Record<string, boolean> = {};
    for (let i = 0; i < props.items.length; i++) {
      const key = contextKey(props.items[i], i);
      if (key in values) {
        toggles[key] = values[key] as boolean;
      }
    }
    props.onSetToggles(toggles);
  }

  return (
    <Form
      navigationTitle="Context"
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Done"
            icon={Icon.ArrowLeft}
            onSubmit={(values) => {
              syncToggles(values);
              const files = (values.attachments as string[]) || [];
              if (files.length > 0) props.onAddFiles(files);
              pop();
            }}
          />
          {props.dispatchActions()}
        </ActionPanel>
      }
    >
      <Form.FilePicker
        id="attachments"
        title="Attach Files"
        allowMultipleSelection
      />
      {props.items.length > 0 && <Form.Separator />}
      {props.items.map((item, i) => (
        <Form.Checkbox
          key={contextKey(item, i)}
          id={contextKey(item, i)}
          title={contextTypeLabel(item)}
          label={item.label}
          defaultValue={defaultEnabled(item, i)}
        />
      ))}
    </Form>
  );
}

function contextTypeLabel(item: ContextItem): string {
  switch (item.type) {
    case "selectedText": return "Selected Text";
    case "clipboard": return "Clipboard";
    case "url": return "Current URL";
    case "screenshot": return "Screenshot";
  }
}

function contextKey(item: ContextItem, index: number): string {
  return `ctx-${item.type}-${index}`;
}

/** Merge recent projects (from API) with session directories, deduped */
function mergeWorkspaces(
  recentProjects: string[],
  sessions: { directory?: string }[],
): string[] {
  const seen = new Set<string>();
  const dirs: string[] = [];
  for (const dir of recentProjects) {
    if (!seen.has(dir)) {
      seen.add(dir);
      dirs.push(dir);
    }
  }
  for (const s of sessions) {
    if (s.directory && !seen.has(s.directory)) {
      seen.add(s.directory);
      dirs.push(s.directory);
    }
  }
  return dirs;
}

function contextListIcon(item: ContextItem): Icon {
  switch (item.type) {
    case "screenshot":
      return Icon.Image;
    case "url":
      return Icon.Link;
    case "selectedText":
      return Icon.TextCursor;
    case "clipboard":
      return Icon.Clipboard;
  }
}
