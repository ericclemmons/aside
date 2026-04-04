import { Form, ActionPanel, Action, Detail, showHUD, showToast, Toast, Icon, popToRoot } from "@raycast/api";
import { useForm, usePromise } from "@raycast/utils";
import { useRef } from "react";
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

const NEW_SESSION = "__new__";

interface FormValues {
  prompt: string;
  session: string;
  [key: string]: unknown; // dynamic context checkbox IDs
}

export default function DispatchCommand() {
  const initialPromptRef = useRef<string | null>(null);

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

  const { handleSubmit, itemProps, setValue } = useForm<FormValues>({
    async onSubmit(values) {
      if (!data) return;

      const prompt = values.prompt?.trim();
      if (!prompt) {
        await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
        return;
      }

      const sessionId = values.session === NEW_SESSION ? undefined : values.session;

      const activeContext = (data.contextItems ?? []).filter(
        (item, i) => values[contextKey(item, i)] === true,
      );
      const fullPrompt = buildPrompt(prompt, activeContext);
      const filePaths = activeContext.filter((c) => c.type === "screenshot").map((c) => c.value);

      const toast = await showToast({ style: Toast.Style.Animated, title: "Dispatching..." });

      const result = await dispatchToOpenCode({
        prompt: fullPrompt,
        server: data.server,
        sessionId,
        filePaths,
        workingDirectory: data.projectDir || undefined,
      });

      if (result.success) {
        toast.hide();

        const original = initialPromptRef.current;
        if (original && original !== prompt) {
          learnFromEdit(original, prompt, data.server).catch(() => {});
        }

        await showHUD("Dispatched to OpenCode");
        await popToRoot();
      } else {
        toast.style = Toast.Style.Failure;
        toast.title = "Dispatch Failed";
        toast.message = result.error;
      }
    },
  });

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

  const sessions = data?.sessions ?? [];
  const contextItems = data?.contextItems ?? [];
  const projectDir = data?.projectDir;

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
        {...itemProps.prompt}
        title="Prompt"
        placeholder="What do you want your agent to do?"
        onChange={(text) => {
          itemProps.prompt.onChange?.(text);
          if (initialPromptRef.current === null && text.trim().length > 0) {
            initialPromptRef.current = text;
          }
        }}
        autoFocus
      />

      <Form.Dropdown {...itemProps.session} title="Session" defaultValue={sessions[0]?.id ?? NEW_SESSION}>
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

function contextKey(item: ContextItem, index: number): string {
  return `ctx-${item.type}-${index}`;
}
