import { Form, ActionPanel, Action, Detail, showHUD, showToast, Toast, Icon, popToRoot } from "@raycast/api";
import { useState, useEffect, useRef } from "react";
import {
  discoverServer,
  fetchSessions,
  fetchProjectDirectory,
  dispatch as dispatchToOpenCode,
  abbreviateHome,
  timeAgo,
  type DiscoveredServer,
  type Session,
} from "./opencode";
import { gatherContext, buildPrompt, type ContextItem } from "./context";
import { learnFromEdit } from "./vocabulary";

const NEW_SESSION = "__new__";

export default function DispatchCommand() {
  const [server, setServer] = useState<DiscoveredServer | null>(null);
  const [serverError, setServerError] = useState(false);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [projectDir, setProjectDir] = useState<string | null>(null);
  const [contextItems, setContextItems] = useState<ContextItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [promptText, setPromptText] = useState("");
  const initialPromptRef = useRef<string | null>(null);

  useEffect(() => {
    async function init() {
      const found = discoverServer();
      if (!found) {
        setServerError(true);
        setIsLoading(false);
        return;
      }
      setServer(found);

      const [s, dir, ctx] = await Promise.all([
        fetchSessions(found),
        fetchProjectDirectory(found),
        gatherContext(),
      ]);

      setSessions(s);
      setProjectDir(dir);
      setContextItems(ctx);
      setIsLoading(false);
    }
    init();
  }, []);

  if (serverError) {
    return (
      <Detail
        markdown="## OpenCode Desktop Not Found\n\nAside requires OpenCode Desktop to be running.\n\nStart OpenCode Desktop and try again."
        actions={
          <ActionPanel>
            <Action.OpenInBrowser title="Get OpenCode Desktop" url="https://opencode.ai" />
          </ActionPanel>
        }
      />
    );
  }

  function contextKey(item: ContextItem, index: number): string {
    return `ctx-${item.type}-${index}`;
  }

  async function handleSubmit(values: Record<string, unknown>) {
    if (!server) return;

    const prompt = (values.prompt as string)?.trim();
    if (!prompt) {
      await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
      return;
    }

    const sessionId = values.session === NEW_SESSION ? undefined : (values.session as string);

    // Collect enabled context items
    const activeContext = contextItems.filter((item, i) => values[contextKey(item, i)] === true);
    const fullPrompt = buildPrompt(prompt, activeContext);
    const filePaths = activeContext.filter((c) => c.type === "screenshot").map((c) => c.value);

    const toast = await showToast({ style: Toast.Style.Animated, title: "Dispatching..." });

    const result = await dispatchToOpenCode({
      prompt: fullPrompt,
      server,
      sessionId,
      filePaths,
      workingDirectory: projectDir || undefined,
    });

    if (result.success) {
      toast.hide();

      const originalText = initialPromptRef.current;
      if (originalText && originalText !== prompt) {
        learnFromEdit(originalText, prompt, server).catch(() => {});
      }

      await showHUD("Dispatched to OpenCode");
      await popToRoot();
    } else {
      toast.style = Toast.Style.Failure;
      toast.title = "Dispatch Failed";
      toast.message = result.error;
    }
  }

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Send" icon={Icon.PaperAirplane} onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextArea
        id="prompt"
        title="Prompt"
        placeholder="What do you want your agent to do?"
        value={promptText}
        onChange={(text) => {
          if (initialPromptRef.current === null && text.trim().length > 0) {
            initialPromptRef.current = text;
          }
          setPromptText(text);
        }}
        autoFocus
      />

      <Form.Dropdown id="session" title="Session" defaultValue={sessions[0]?.id ?? NEW_SESSION}>
        <Form.Dropdown.Item value={NEW_SESSION} title="New Session" icon={Icon.Plus} />
        {sessions.map((s) => (
          <Form.Dropdown.Item
            key={s.id}
            value={s.id}
            title={s.name}
            icon={Icon.Message}
            keywords={[s.directory ? abbreviateHome(s.directory) : "", timeAgo(s.updatedAt)]}
          />
        ))}
      </Form.Dropdown>

      {contextItems.length > 0 && <Form.Separator />}

      {contextItems.map((item, i) => (
        <Form.Checkbox
          key={contextKey(item, i)}
          id={contextKey(item, i)}
          label={item.label}
          defaultValue={item.defaultEnabled}
        />
      ))}

      {projectDir && (
        <>
          <Form.Separator />
          <Form.Description title="Project" text={abbreviateHome(projectDir)} />
        </>
      )}
    </Form>
  );
}
