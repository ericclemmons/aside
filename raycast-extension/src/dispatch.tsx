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

interface FormValues {
  prompt: string;
  [key: string]: unknown; // dynamic context checkbox IDs
}

export default function DispatchCommand() {
  const initialPromptRef = useRef<string | null>(null);
  const targetSessionRef = useRef<string | undefined>(undefined);

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

  const { handleSubmit, itemProps } = useForm<FormValues>({
    async onSubmit(values) {
      if (!data) return;

      const prompt = values.prompt?.trim();
      if (!prompt) {
        await showToast({ style: Toast.Style.Failure, title: "Prompt is empty" });
        return;
      }

      const sessionId = targetSessionRef.current;

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
  const recent = sessions[0];

  function submitTo(sessionId: string | undefined) {
    targetSessionRef.current = sessionId;
    return handleSubmit;
  }

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          {recent && (
            <Action.SubmitForm
              title={`Send to ${recent.name}`}
              icon={Icon.PaperAirplane}
              onSubmit={(values) => submitTo(recent.id)(values as FormValues)}
            />
          )}
          <Action.SubmitForm
            title="Send to New Session"
            icon={Icon.Plus}
            shortcut={{ modifiers: ["cmd"], key: "enter" }}
            onSubmit={(values) => submitTo(undefined)(values as FormValues)}
          />
          {sessions.length > 1 && (
            <ActionPanel.Section title="Send to Session">
              {sessions.slice(1).map((s) => (
                <Action.SubmitForm
                  key={s.id}
                  title={s.name}
                  icon={Icon.Message}
                  onSubmit={(values) => submitTo(s.id)(values as FormValues)}
                />
              ))}
            </ActionPanel.Section>
          )}
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

      {contextItems.length > 0 && <Form.Separator />}

      {contextItems.map((item, i) => (
        <Form.Checkbox
          key={contextKey(item, i)}
          id={contextKey(item, i)}
          label={item.label}
          defaultValue={item.defaultEnabled}
        />
      ))}

      {(recent || projectDir) && <Form.Separator />}
      {recent && (
        <Form.Description
          title="Session"
          text={`${recent.name} · ${timeAgo(recent.updatedAt)}`}
        />
      )}
      {projectDir && <Form.Description title="Project" text={abbreviateHome(projectDir)} />}
    </Form>
  );
}

function contextKey(item: ContextItem, index: number): string {
  return `ctx-${item.type}-${index}`;
}
