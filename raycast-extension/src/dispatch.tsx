import {
  List,
  ActionPanel,
  Action,
  Detail,
  showHUD,
  showToast,
  Toast,
  Icon,
  popToRoot,
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
  const sessions = data?.sessions ?? [];
  const projectDir = data?.projectDir;

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
    async (sessionId: string | undefined) => {
      if (!data) return;

      const text = prompt.trim();
      if (!text) {
        await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
        return;
      }

      const activeContext = contextItems.filter((item, i) => isItemEnabled(item, i));
      const fullPrompt = buildPrompt(text, activeContext);
      const filePaths = activeContext.filter((c) => c.type === "screenshot").map((c) => c.value);

      const toast = await showToast({ style: Toast.Style.Animated, title: "Dispatching..." });

      const result = await dispatchToOpenCode({
        prompt: fullPrompt,
        server: data.server,
        sessionId,
        filePaths,
        workingDirectory: projectDir || sessions[0]?.directory || undefined,
      });

      if (result.success) {
        toast.hide();
        const original = initialPromptRef.current;
        if (original && original !== text) {
          learnFromEdit(original, text, data.server).catch(() => {});
        }
        await showHUD("Dispatched to OpenCode");
        await popToRoot();
      } else {
        toast.style = Toast.Style.Failure;
        toast.title = "Dispatch Failed";
        toast.message = result.error;
      }
    },
    [data, prompt, contextItems, toggledItems, projectDir],
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
          title="New Session"
          icon={Icon.Plus}
          shortcut={{ modifiers: ["cmd"], key: "return" }}
          onAction={() => doDispatch(undefined)}
        />
        {sessions.length > 0 && (
          <ActionPanel.Section title="Send to Session">
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
        return `### URL\n\n${item.value}`;
      case "selectedText":
        return `### Selected Text\n\n\`\`\`\n${item.value.slice(0, 1000)}\n\`\`\``;
      case "clipboard":
        return `### Clipboard\n\n\`\`\`\n${item.value.slice(0, 1000)}\n\`\`\``;
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
      {hasContext && (
        <List.Section title="Context" subtitle={projectDir ? abbreviateHome(projectDir) : undefined}>
          {contextItems.map((item, i) => {
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
      )}

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
