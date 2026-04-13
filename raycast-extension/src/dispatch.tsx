import {
  List,
  ActionPanel,
  Action,
  Detail,
  showHUD,
  showToast,
  Toast,
  Icon,
  closeMainWindow,
  Color,
  Keyboard,
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
  const sessions = (data?.sessions ?? []).filter((s) => s.directory && s.directory !== "/");
  const projectDir = data?.projectDir;
  const recentProjects = data?.recentProjects ?? [];
  const defaultWorkDir = projectDir || recentProjects[0] || sessions[0]?.directory;
  const workspaceDirs = mergeWorkspaces(recentProjects, sessions);

  // Build ordered dispatch targets: new session in latest workspace, then recent sessions, then other workspaces
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

  function toggleItem(item: ContextItem, index: number) {
    const key = contextKey(item, index);
    setToggledItems((prev) => ({
      ...prev,
      [key]: !isItemEnabled(item, index),
    }));
  }

  const doDispatch = useCallback(
    async (sessionId: string | undefined, workDirOverride?: string) => {
      if (!data) return;

      const text = prompt.trim();
      if (!text) {
        await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
        return;
      }

      const activeContext = contextItems.filter((item, i) => isItemEnabled(item, i));
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
    [data, prompt, contextItems, toggledItems, defaultWorkDir],
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

  /** Actions available on every item — dispatch targets with Cmd+1-9 shortcuts */
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

  function detailMarkdown(item: ContextItem): string {
    switch (item.type) {
      case "screenshot": {
        const encoded = encodeURI(`file://${item.value}`);
        return `![Screenshot](${encoded})`;
      }
      case "url":
        return item.value;
      case "selectedText":
        return `\`\`\`\n${item.value.slice(0, 1000)}\n\`\`\``;
      case "clipboard":
        return `\`\`\`\n${item.value.slice(0, 1000)}\n\`\`\``;
    }
  }

  const hasContext = contextItems.length > 0;

  // Build hint string for placeholder
  const hint = targets.length > 0
    ? `↵ toggle · ⌘1 ${targets[0].label.split(" in ").pop() || "send"}`
    : "↵ toggle";

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
      isShowingDetail={hasContext}
    >
      {/* Context section */}
      {hasContext && contextSections(contextItems).map(([sectionTitle, items]) => (
        <List.Section key={sectionTitle} title={sectionTitle}>
          {items.map(([item, i]) => {
            const enabled = isItemEnabled(item, i);
            return (
              <List.Item
                key={contextKey(item, i)}
                icon={contextListIcon(item)}
                title={item.label}
                accessories={[
                  enabled
                    ? { icon: { source: Icon.Checkmark, tintColor: Color.Green }, tooltip: "Included" }
                    : { icon: { source: Icon.Circle, tintColor: Color.SecondaryText }, tooltip: "Excluded" },
                ]}
                detail={<List.Item.Detail markdown={detailMarkdown(item)} />}
                actions={
                  <ActionPanel>
                    <Action
                      title={enabled ? "Exclude from Prompt" : "Include in Prompt"}
                      icon={enabled ? Icon.XMarkCircle : Icon.CheckCircle}
                      onAction={() => toggleItem(item, i)}
                    />
                    {dispatchActions()}
                  </ActionPanel>
                }
              />
            );
          })}
        </List.Section>
      ))}

      {/* Dispatch targets section — always visible */}
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

      {!hasContext && targets.length === 0 && (
        <List.EmptyView
          title="No context or sessions"
          description="Type a prompt and press Enter to send"
        />
      )}
    </List>
  );
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

/** Group context items into sections by type, preserving original indices */
function contextSections(items: ContextItem[]): [string, [ContextItem, number][]][] {
  const groups: Record<string, [ContextItem, number][]> = {};
  const order: string[] = [];

  for (let i = 0; i < items.length; i++) {
    const title = sectionTitle(items[i]);
    if (!groups[title]) {
      groups[title] = [];
      order.push(title);
    }
    groups[title].push([items[i], i]);
  }

  return order.map((title) => [title, groups[title]]);
}

function sectionTitle(item: ContextItem): string {
  switch (item.type) {
    case "selectedText": return "Text";
    case "clipboard": return "Clipboard";
    case "url": return "Links";
    case "screenshot": return "Screenshots";
  }
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
