import { List, ActionPanel, Action, Icon, confirmAlert, Alert, showToast, Toast } from "@raycast/api";
import { useState } from "react";
import { loadVocabulary, vocabPath, type VocabularyEntry } from "./vocabulary";
import { writeFileSync } from "fs";

export default function VocabularyListCommand() {
  const [entries, setEntries] = useState<VocabularyEntry[]>(loadVocabulary());

  function save(updated: VocabularyEntry[]) {
    setEntries(updated);
    writeFileSync(vocabPath(), JSON.stringify(updated, null, 2));
  }

  async function clearAll() {
    if (
      await confirmAlert({
        title: "Clear All Vocabulary",
        message: `Remove all ${entries.length} learned words?`,
        primaryAction: { title: "Clear", style: Alert.ActionStyle.Destructive },
      })
    ) {
      save([]);
      await showToast({ style: Toast.Style.Success, title: "Vocabulary cleared" });
    }
  }

  return (
    <List searchBarPlaceholder="Filter vocabulary...">
      <List.EmptyView
        title="No Vocabulary Learned"
        description="Edit a prompt before dispatching and Aside will learn your corrections"
        icon={Icon.Book}
      />

      {entries.map((entry, i) => (
        <List.Item
          key={`${entry.from}-${entry.to}-${i}`}
          title={`${entry.from} -> ${entry.to}`}
          subtitle={`seen ${entry.count}x`}
          accessories={[{ text: new Date(entry.lastSeen).toLocaleDateString() }]}
          icon={Icon.Book}
          actions={
            <ActionPanel>
              <Action
                title="Remove"
                icon={Icon.Trash}
                style={Action.Style.Destructive}
                onAction={() => save(entries.filter((e) => !(e.from === entry.from && e.to === entry.to)))}
              />
              <Action
                title="Clear All"
                icon={Icon.Trash}
                style={Action.Style.Destructive}
                shortcut={{ modifiers: ["cmd", "shift"], key: "delete" }}
                onAction={clearAll}
              />
              <Action.CopyToClipboard title="Copy Correction" content={`${entry.from} -> ${entry.to}`} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
