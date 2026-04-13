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
} from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { useState, useCallback, useRef } from "react";
import {
  discoverServer,
  fetchSessions,
  fetchProjectDirectory,
  dispatch as dispatchToOpenCode,
  abbreviateHome,
  timeAgo,
} from "./opencode";
import { gatherContext, buildPrompt, type ContextItem } from "./context";
import { learnFromEdit } from "./vocabulary";

export default function DispatchCommand() {
  const [prompt, setPrompt] = useState("");
  const initialPromptRef = useRef<string | null>(null);
  const [toggledItems, setToggledItems] = useState<Record<string, boolean>>({});

  const { data, isLoading, error } = usePromise(async () => {
    const server = discoverServer();
    if (!server) throw new Error("not_found");

    const [sessions, projectDir, contextItems] = await Promise.all([
      fetchSessions(server),
      fetchProjectDirectory(server),
      gatherContext(),
    ]);

    return { server, sessions, projectDir, contextItems };
  });

  const contextItems = data?.contextItems ?? [];
  const sessions = (data?.sessions ?? []).filter((s) => s.directory && s.directory !== "/");
  const projectDir = data?.projectDir;
  const defaultWorkDir = projectDir || sessions[0]?.directory;
  const workspaceDirs = uniqueWorkspaces(sessions);

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

      const workDir = workingDirectory;
      dispatchToOpenCode({
        prompt: fullPrompt,
        server: data.server,
        sessionId,
        filePaths,
        workingDirectory: workDir,
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

  function sessionActions() {
    return (
      <>
        <Action
          title={`New Session in ${abbreviateHome(defaultWorkDir || "~")}`}
          icon={Icon.Plus}
          shortcut={{ modifiers: ["cmd"], key: "return" }}
          onAction={() => doDispatch(undefined)}
        />
        {workspaceDirs.length > 1 && (
          <ActionPanel.Section title="New Session in…">
            {workspaceDirs
              .filter((dir) => dir !== defaultWorkDir)
              .map((dir) => (
                <Action
                  key={`new-${dir}`}
                  title={abbreviateHome(dir)}
                  icon={Icon.Plus}
                  onAction={() => doDispatch(undefined, dir)}
                />
              ))}
          </ActionPanel.Section>
        )}
        {sessions.length > 0 && (
          <ActionPanel.Section title="Add to Session">
            {sessions.map((s) => (
              <Action
                key={s.id}
                title={`${s.name} · ${timeAgo(s.updatedAt)}`}
                icon={Icon.Message}
                onAction={() => doDispatch(s.id)}
              />
            ))}
          </ActionPanel.Section>
        )}
      </>
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

  return (
    <List
      isLoading={isLoading}
      searchBarPlaceholder="Prompt…  ⌘↵ to send"
      onSearchTextChange={(text) => {
        setPrompt(text);
        if (initialPromptRef.current === null && text.trim().length > 0) {
          initialPromptRef.current = text;
        }
      }}
      filtering={false}
      isShowingDetail={hasContext}
    >
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
                    {sessionActions()}
                  </ActionPanel>
                }
              />
            );
          })}
        </List.Section>
      ))}

      {!hasContext && (
        <List.EmptyView
          title="No context detected"
          description="Type a prompt and press ⌘↵ to send"
          actions={
            <ActionPanel>
              {sessionActions()}
            </ActionPanel>
          }
        />
      )}
    </List>
  );
}

function contextKey(item: ContextItem, index: number): string {
  return `ctx-${item.type}-${index}`;
}

/** Unique workspace directories from sessions, ordered by most recent */
function uniqueWorkspaces(sessions: { directory?: string }[]): string[] {
  const seen = new Set<string>();
  const dirs: string[] = [];
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
