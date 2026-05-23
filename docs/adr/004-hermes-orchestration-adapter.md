# ADR 004: Hermes Orchestration Adapter

## 狀態

Accepted

## 背景

Agentic Delivery System 已有 repo-local core contracts：

- `agentic/pipeline.yaml`
- `agentic/profiles/*.yaml`
- planning manifest
- implementation manifest
- scripts
- prompts
- review outputs

這些 contract 讓每個 delivery run 可追蹤、可重跑、可審查。下一步需要讓 Hermes Agent 成為內部 execution host，讓使用者可以提交 goal，由 Hermes 協調 planning 與 implementation pipeline。

若直接把 pipeline logic 寫進 Hermes prompt 或 memory，會造成：

- state authority 分裂。
- failure recovery 不可重建。
- Hermes crash 後無法可靠恢復。
- scripts 與 Hermes 行為不一致。
- review-only 原則可能被繞過。

## 決策

採用 **Hermes Orchestration Adapter**。

Hermes 作為 execution host，只能透過 documented actions 呼叫 repo-local commands。Repo-local manifest 是 authoritative state store。Hermes memory 只作為 execution context。

每個 Hermes action 必須先在 `agentic/hermes-actions.yaml` 定義，並對應到可人工重跑的 repo-local command。

## 必須遵守

- Hermes 不得取代 `manifest.yaml` 或 `implementation-manifest.yaml`。
- Hermes 不得直接修改 profile source of truth。
- Hermes 不得模擬 Claude Code agency-agents review。
- Hermes 不得在 manifest 未記錄時宣稱 step completed。
- Hermes 不得執行未定義於 `agentic/hermes-actions.yaml` 的 delivery pipeline action。
- 每個 implementation slice 必須通過 AIT + Claude Code code review。

## Slice 實作政策

Hermes adapter implementation 必須切成小 slice。

每個 slice 必須：

- 有明確 scope。
- 有對應文件或 contract。
- 有驗證命令。
- 有 AIT code review。
- 修正該輪 review 發現的所有問題。
- reviewer 通過後才可進下一個 slice。
- 最多 5 輪 review。

第 5 輪仍未通過時，該 slice 必須停止並標記為 `blocked_human_decision_required`。

## Code Review 執行規則

每個 slice 完成後，使用 AIT 呼叫 Claude Code：

```bash
ait run --adapter claude-code --stdin none --apply never --review never --format json -- \
  "$(command -v claude)" \
  --add-dir "$PWD" \
  --agent engineering-software-architect \
  -p "<slice code review prompt>"
```

Claude Code reviewer 只做審查，不直接修改檔案。Codex/Orchestrator 負責修正與整合。

## 後果

### 正面

- Hermes 能成為真正的內部交付 execution host。
- Core pipeline 保持 repo-local、可重跑、可審查。
- 每個 action 都有 command-level trace。
- crash / timeout 後可依 manifest 恢復。
- 小 slice review gate 降低大型 agentic system 一次性失敗風險。

### 代價

- 初期需要維護 action contract、slice plan 與 review logs。
- 實作速度會慢於直接寫 Hermes runtime，但可控性更高。
- AIT / Claude Code credential 會是 slice review blocker。

## 驗收標準

- `docs/architecture/hermes-orchestration-adapter.md` 存在。
- `agentic/hermes-actions.yaml` 存在且 YAML 可解析。
- `agentic/prompts/hermes-orchestrator.md` 存在。
- `agentic/prompts/slice-code-review.md` 存在。
- `docs/backlog/hermes-adapter-implementation-slices.md` 存在。
- `scripts/validate-agentic-system.sh` 會檢查上述檔案。
- 本 ADR 與 H0 文件/contract slice 有 AIT review output。
- 每個後續 implementation slice 都有 AIT code review output。

## 相關文件

- `docs/architecture/agentic-delivery-system.md`
- `docs/architecture/hermes-orchestration-adapter.md`
- `docs/backlog/hermes-adapter-implementation-slices.md`
- `agentic/hermes-actions.yaml`
- `agentic/prompts/hermes-orchestrator.md`
- `agentic/prompts/slice-code-review.md`
