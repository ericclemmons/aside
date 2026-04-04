import { List, ActionPanel, Action, Icon, confirmAlert, Alert, showToast, Toast } from "@raycast/api";
import { useState } from "react";
import { loadCustomWords, customWordsPath } from "./vocabulary";
import { writeFileSync } from "fs";

export default function VocabularyListCommand() {
  const [words, setWords] = useState<string[]>(loadCustomWords());

  function save(updated: string[]) {
    setWords(updated);
    writeFileSync(customWordsPath(), JSON.stringify(updated, null, 2));
  }

  async function clearAll() {
    if (
      await confirmAlert({
        title: "Clear All Custom Words",
        message: `Remove all ${words.length} words?`,
        primaryAction: { title: "Clear", style: Alert.ActionStyle.Destructive },
      })
    ) {
      save([]);
      await showToast({ style: Toast.Style.Success, title: "Custom words cleared" });
    }
  }

  return (
    <List searchBarPlaceholder="Filter custom words...">
      <List.EmptyView
        title="No Custom Words"
        description="Edit a prompt before dispatching and Aside will learn new words for transcription"
        icon={Icon.Book}
      />

      {words.map((word, i) => (
        <List.Item
          key={`${word}-${i}`}
          title={word}
          icon={Icon.Book}
          actions={
            <ActionPanel>
              <Action
                title="Remove"
                icon={Icon.Trash}
                style={Action.Style.Destructive}
                onAction={() => save(words.filter((_, j) => j !== i))}
              />
              <Action
                title="Clear All"
                icon={Icon.Trash}
                style={Action.Style.Destructive}
                shortcut={{ modifiers: ["cmd", "shift"], key: "delete" }}
                onAction={clearAll}
              />
              <Action.CopyToClipboard title="Copy Word" content={word} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
