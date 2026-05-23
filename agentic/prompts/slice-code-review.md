請你以 Claude Code reviewer 身分審查 Agentic Delivery System 的 implementation slice。

你只做 code review / docs-contract review，不修改任何檔案，不模擬其他 reviewer。

## Slice Metadata

- Slice ID: {{SLICE_ID}}
- Slice goal: {{SLICE_GOAL}}
- Review round: {{REVIEW_ROUND}} / 5
- Repo root: {{DOC_ROOT}}

## 必讀文件

1. `docs/architecture/agentic-delivery-system.md`
2. `docs/architecture/hermes-orchestration-adapter.md`
3. `docs/adr/003-agentic-delivery-boundary.md`
4. `docs/adr/004-hermes-orchestration-adapter.md`
5. `docs/backlog/hermes-adapter-implementation-slices.md`
6. `agentic/hermes-actions.yaml`

## Changed Files

{{CHANGED_FILES}}

## Validation Results

{{VALIDATION_RESULTS}}

## Review Requirements

請檢查：

- Slice 是否符合 `docs/backlog/hermes-adapter-implementation-slices.md` 定義的 scope。
- 是否有文件或 contract 可對應實作。
- 是否維持 profile-driven，不把任何 profile-specific strategy 寫死到 core pipeline。
- 是否保持 repo manifest 為 authoritative state。
- 是否避免 Hermes memory 取代 manifest。
- 是否每個 action 都可人工用 repo-local command 重跑。
- 是否沒有模擬 Claude Code agency-agents review。
- 是否沒有修改 profile source of truth 或產品策略。
- 是否 shell / YAML / manifest validation 足夠。
- 是否有錯誤處理、failure state、retry 或 human decision 邊界。

## 輸出格式

請使用繁體中文，並輸出：

```yaml
slice_review:
  slice_id: "{{SLICE_ID}}"
  round: "{{REVIEW_ROUND}}"
  status: pass | request_changes | blocked
  summary: string
  findings:
    - severity: high | medium | low
      file: string
      line: integer | null
      issue: string
      required_change: string
  validation_gaps:
    - string
  decision:
    recommendation: approve | request_changes | block
    reason: string
```

若沒有 blocking issue，請明確給 `status: pass` 與 `recommendation: approve`。
