import {
  Form,
  ActionPanel,
  Action,
  showHUD,
  showToast,
  Toast,
  Icon,
  getPreferenceValues,
  popToRoot,
} from "@raycast/api";
import { useState, useEffect } from "react";
import {
  discoverServer,
  fetchSessions,
  fetchProjectDirectory,
  dispatch as dispatchToOpenCode,
  timeAgo,
  abbreviateHome,
  type DiscoveredServer,
  type Session,
} from "./opencode";
import { gatherContext, buildPrompt, type ContextItem } from "./context";

export default function DispatchCommand() {
  const [server, setServer] = useState<DiscoveredServer | null>(null);
  const [serverError, setServerError] = useState<string | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [projectDir, setProjectDir] = useState<string | null>(null);
  const [contextItems, setContextItems] = useState<ContextItem[]>([]);
  const [enabledContextIds, setEnabledContextIds] = useState<Set<string>>(new Set());
  const [promptText, setPromptText] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isDispatching, setIsDispatching] = useState(false);

  useEffect(() => {
    async function init() {
      // Discover server
      const found = discoverServer();
      if (!found) {
        setServerError("OpenCode Desktop is not running. Start it first, then try again.");
        setIsLoading(false);
        return;
      }
      setServer(found);

      // Fetch sessions, project dir, and context in parallel
      const [fetchedSessions, fetchedDir, fetchedContext] = await Promise.all([
        fetchSessions(found),
        fetchProjectDirectory(found),
        gatherContext(),
      ]);

      setSessions(fetchedSessions);
      setProjectDir(fetchedDir);
      setContextItems(fetchedContext);

      // Enable items that are defaultEnabled
      const enabled = new Set<string>();
      fetchedContext.forEach((item, i) => {
        if (item.defaultEnabled) enabled.add(contextKey(item, i));
      });
      setEnabledContextIds(enabled);

      setIsLoading(false);
    }
    init();
  }, []);

  function contextKey(item: ContextItem, index: number): string {
    return `${item.type}-${index}`;
  }

  function toggleContext(key: string, enabled: boolean) {
    setEnabledContextIds((prev) => {
      const next = new Set(prev);
      if (enabled) next.add(key);
      else next.delete(key);
      return next;
    });
  }

  async function handleDispatch(sessionId?: string) {
    if (!server) return;
    if (!promptText.trim()) {
      await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
      return;
    }

    setIsDispatching(true);

    // Build context from enabled items
    const activeContext = contextItems.filter((item, i) => enabledContextIds.has(contextKey(item, i)));
    const fullPrompt = buildPrompt(promptText, activeContext);

    // Collect file paths for screenshots
    const filePaths = activeContext.filter((c) => c.type === "screenshot").map((c) => c.value);

    const result = await dispatchToOpenCode({
      prompt: fullPrompt,
      server,
      sessionId,
      filePaths,
      workingDirectory: projectDir || undefined,
    });

    setIsDispatching(false);

    if (result.success) {
      await showHUD("Dispatched to OpenCode");
      await popToRoot();
    } else {
      await showToast({
        style: Toast.Style.Failure,
        title: "Dispatch failed",
        message: result.error,
      });
    }
  }

  if (serverError) {
    return (
      <Form
        actions={
          <ActionPanel>
            <Action.OpenInBrowser title="Get OpenCode Desktop" url="https://opencode.ai" />
          </ActionPanel>
        }
      >
        <Form.Description title="OpenCode Not Found" text={serverError} />
      </Form>
    );
  }

  const recentSession = sessions[0];

  return (
    <Form
      isLoading={isLoading || isDispatching}
      actions={
        <ActionPanel>
          <Action
            title={recentSession ? `Send to "${recentSession.name}"` : "Send to New Session"}
            icon={Icon.PaperAirplane}
            onAction={() => handleDispatch(recentSession?.id)}
          />
          <Action
            title="Send to New Session"
            icon={Icon.Plus}
            shortcut={{ modifiers: ["cmd"], key: "return" }}
            onAction={() => handleDispatch(undefined)}
          />
          {sessions.length > 0 && (
            <Action.Push
              title="Choose Session..."
              icon={Icon.List}
              shortcut={{ modifiers: ["cmd"], key: "k" }}
              target={
                <SessionPicker
                  sessions={sessions}
                  onSelect={(id) => handleDispatch(id)}
                />
              }
            />
          )}
        </ActionPanel>
      }
    >
      <Form.TextArea
        id="prompt"
        title="Prompt"
        placeholder="What do you want your agent to do?"
        value={promptText}
        onChange={setPromptText}
        autoFocus
      />

      {contextItems.length > 0 && <Form.Separator />}

      {contextItems.map((item, i) => {
        const key = contextKey(item, i);
        return (
          <Form.Checkbox
            key={key}
            id={key}
            label={item.label}
            value={enabledContextIds.has(key)}
            onChange={(val) => toggleContext(key, val)}
          />
        );
      })}

      {projectDir && (
        <>
          <Form.Separator />
          <Form.Description title="Project" text={abbreviateHome(projectDir)} />
        </>
      )}
    </Form>
  );
}

function SessionPicker(props: { sessions: Session[]; onSelect: (id: string) => void }) {
  // This is used as an Action.Push target, but since Action.Push expects
  // a React element, we render a Form-based session selector
  const { sessions, onSelect } = props;
  const [selectedSession, setSelectedSession] = useState(sessions[0]?.id || "");

  return (
    <Form
      actions={
        <ActionPanel>
          <Action
            title="Select Session"
            icon={Icon.CheckCircle}
            onAction={() => onSelect(selectedSession)}
          />
        </ActionPanel>
      }
    >
      <Form.Dropdown id="session" title="Session" value={selectedSession} onChange={setSelectedSession}>
        {sessions.map((s) => (
          <Form.Dropdown.Item
            key={s.id}
            value={s.id}
            title={s.name}
            icon={Icon.Message}
          />
        ))}
      </Form.Dropdown>
    </Form>
  );
}
