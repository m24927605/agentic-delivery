請你以 Claude Code agency-agent 角色 {{AGENT_NAME}} 針對 profile `{{PROFILE_ID}}`（{{PROFILE_NAME}}）進行獨立審查。你只做審查，不修改任何檔案，也不要合議或模擬其他角色。

重要：請讀取 DOC_ROOT 下的以下檔案。DOC_ROOT 為：{{DOC_ROOT}}

必讀檔案：
{{REQUIRED_FILES}}

主要策略來源：{{PRIMARY_STRATEGY_DOC}}
產品/任務定位：{{PRODUCT_POSITIONING}}

請從 {{AGENT_NAME}} 角度審查：
{{REVIEW_QUESTIONS}}

請用繁體中文輸出，格式如下：
{{OUTPUT_SECTIONS}}

只輸出審查意見，不修改檔案。
