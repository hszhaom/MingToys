# AGENTS.md - PetStorie 项目工作规范

本文件适用于当前仓库 `PetStorie`，这是一个面向海外自然流量的英文宠物内容站，使用 Jekyll/GitHub Pages 发布。后续所有新增、改写、修复、页面结构调整，都必须优先兼顾 SEO、Google 收录和 GitHub Pages 构建稳定性。

## 1. 项目结构

- `_posts/`: 文章目录，文件名格式必须保持 `YYYY-MM-DD-slug.md`。
- `_layouts/default.html`: 全站基础 HTML、meta、canonical、CSS 引用。
- `_layouts/post.html`: 文章页布局、正文渲染、Article JSON-LD。
- `assets/images/`: 文章封面图和正文图片。
- `pages/archive.html`: 归档页。
- `index.html`: 首页文章列表。
- `_config.yml`: Jekyll 配置、域名、permalink、分页。
- `sitemap.xml`: 动态生成站点地图。
- `robots.txt`: 搜索引擎抓取规则。

## 2. 回复与协作规则

- 默认使用中文回复。
- 代码、文件名、变量名、HTML class、schema 字段使用英文。
- 修改前先理解现有结构，不随意重构。
- 不改变已有文章 URL，除非用户明确要求。
- 不删除已有文章、图片、统计脚本或 sitemap/robots 规则，除非确认有害。
- 修改后要说明改动文件、SEO 目的和潜在风险。

## 3. GitHub Pages / Jekyll Front Matter 规则

所有 Markdown 文章必须使用有效 YAML front matter。

必须包含：

```yaml
---
title: "Dog Breed Guide: Main Keyword and Search Intent"
description: "A concise SEO description that explains what the reader will learn."
cover: /assets/images/example-cover.jpg
layout: post
---
```

强制规则：

- `title` 和 `description` 默认使用双引号包裹。
- 只要字段中包含英文冒号 `:`, 单引号, 双引号, `&`, 问号, 逗号较多，必须加双引号。
- 不使用未转义的裸冒号，例如不要写：

```yaml
title: French Bulldog Breed Guide: Temperament and Care
```

- 正确写法：

```yaml
title: "French Bulldog Breed Guide: Temperament and Care"
```

- 如标题必须避免 YAML 解析风险，也可以使用中文冒号 `：`，但优先使用双引号保留英文 SEO 标题。
- `description` 控制在约 140-160 个英文字符，必须自然包含主关键词。
- `cover` 使用站内绝对路径，例如 `/assets/images/frenchbulldog-cover.jpg`。
- 不在 front matter 中使用中文标点作为 SEO 关键词主体。

## 4. 文章 SEO 改写标准

当前站点的历史文章偏“趣味犬种介绍”。后续改写目标是升级为可被 Google 理解和收录的搜索型页面。

文章优先采用以下结构：

```markdown
Intro paragraph answering the main search intent.

![Descriptive image alt text]({{ site.url }}/assets/images/example-main.jpg)

## Breed Quick Facts

| Trait | What to Expect |
|---|---|
| Size | ... |
| Temperament | ... |
| Energy level | ... |
| Grooming needs | ... |
| Common concerns | ... |

## Temperament

## Exercise Needs

## Grooming and Shedding

## Common Health Issues

## Feeding and Weight Control

## Training Tips

## Pros and Cons

## Is This Breed Right for You?

## FAQ

### Are ... good family dogs?

### Do ... bark a lot?

### Are ... good for apartments?

## Final Verdict
```

每篇文章必须满足：

- 首段直接回答用户搜索意图，不写空泛开场。
- 标题包含主关键词，例如 `French Bulldog Breed Guide`。
- 至少包含一个 `Quick Facts` 表格。
- 至少包含一个 `Pros and Cons` 表格或列表。
- 至少包含 4-6 个 FAQ 问题。
- 至少有 2 个站内相关文章内链。
- 图片 alt 必须描述图片内容，不堆关键词。
- 内容面向英文用户，正文使用自然英文。
- 不写未经确认的医疗结论；健康建议必须提示咨询 veterinarian。
- 不承诺绝对化结论，例如 `always`, `never`, `guaranteed`，除非事实非常明确。

## 5. Google 收录与自然流量要求

新增或修改内容时必须考虑：

- 页面是否满足明确搜索意图。
- 标题是否适合 Google SERP 点击。
- description 是否可作为搜索摘要。
- 是否有唯一价值，而不是泛泛复述。
- 是否有内部链接指向相关主题。
- 是否存在重复或相互竞争的文章。
- 是否适合加入专题聚合页。
- 是否有清晰的 H2/H3 层级。
- 是否避免标题党、过度夸张和低质量 AI 文风。

优先优化以下页面类型：

- 犬种指南：`Breed Guide`, `Temperament`, `Care`, `Health Issues`, `Cost`。
- 对比页面：`Breed A vs Breed B`。
- 场景页面：`Best Dogs for Apartments`, `Best Family Dogs`, `Low-Shedding Dog Breeds`。
- 问题页面：`Can dogs eat ...`, `Why does my dog ...`。
- 工具/清单页面：feeding chart, puppy checklist, grooming checklist。

## 6. 内容质量与 E-E-A-T

宠物健康、护理、饮食内容属于需要谨慎处理的主题。

要求：

- 使用清晰、可执行、保守的建议。
- 涉及疾病、药物、异常症状时，必须建议咨询 veterinarian。
- 区分常见现象和需要就医的风险信号。
- 避免伪专业语气和无法验证的夸张说法。
- 不编造兽医背书、研究数据、作者资质或外部引用。
- 如果引用外部信息，优先使用权威来源并保留链接。

## 7. 内链规范

每篇改写文章至少添加 2 个相关内链。

内链格式：

```markdown
[Pug guide]({{ site.url }}/posts/2026/06/05/pug-wrinkly-snoring-little-home-potato/)
```

规则：

- 使用已存在的文章 URL。
- 锚文本自然，避免重复堆关键词。
- 内链要帮助用户比较相关犬种或继续阅读。
- 不链接不存在的页面。

## 8. 图片规范

- 文章封面字段使用 `cover`。
- 正文图片使用 `{{ site.url }}/assets/images/...`。
- alt 文本写图片真实内容，例如：

```markdown
![Adult French Bulldog with fawn coat and upright bat ears]({{ site.url }}/assets/images/frenchbulldog-main.jpg)
```

- 不使用空 alt，除非纯装饰图。
- 不插入外部热链图片。
- 不随意改图片文件名，避免破坏已有引用。

## 9. 技术 SEO 规范

修改模板时必须保持：

- 每页有唯一 `<title>`。
- 每页有 meta description。
- 每页有 canonical。
- 文章页保留 Article JSON-LD。
- `sitemap.xml` 能包含所有 posts。
- `robots.txt` 不阻止文章、图片、CSS。
- 页面语言为 `en`。
- 移动端 viewport 不删除。

如修改 `_layouts/default.html` 或 `_layouts/post.html`，必须检查 SEO 标签和 JSON-LD 是否仍然有效。

## 10. 常见问题优先修复

当前项目中已观察到的问题，后续修改时应优先修：

- 文章中存在乱码，例如 `鈥檙e`, `鈥檚`, `鈥檒l`。
- 部分 front matter 中 `title` 含英文冒号但未加双引号。
- 个别文章 title/description 与文件主题不匹配，例如 Labrador 文件曾出现 Schnauzer 元信息。
- 历史文章标题偏娱乐化，需要升级为搜索意图型标题。
- 缺少专题聚合页和系统内链。

## 11. 改写优先级

优先改写高搜索价值犬种：

1. French Bulldog
2. Golden Retriever
3. Labrador Retriever
4. German Shepherd
5. Pug
6. Pembroke Welsh Corgi
7. Shiba Inu
8. Siberian Husky
9. Beagle
10. Dachshund

每次改写建议保持小批量，方便检查构建和收录影响。

## 12. 发布前检查清单

每次新增或修改文章后，检查：

- Front matter 是否有效 YAML。
- `title` 和 `description` 是否加双引号。
- 是否保留原 permalink/文件名。
- 是否没有乱码。
- 是否至少包含 2 个内链。
- 是否包含 Quick Facts、Pros/Cons、FAQ。
- 图片路径是否存在。
- Markdown 表格是否格式正确。
- 没有裸露的本地 Windows 路径。
- 没有无依据的医疗、安全或训练绝对化声明。

## 13. 禁止事项

- 不批量生成低质量相似文章。
- 不做关键词堆砌。
- 不为了 SEO 编造作者经验、兽医审核或引用。
- 不修改 URL slug 来追求关键词，除非用户明确接受重定向和收录波动。
- 不使用隐藏文本、无意义外链、采集内容或搜索引擎作弊策略。
- 不把宠物医疗建议写成诊断或治疗方案。

