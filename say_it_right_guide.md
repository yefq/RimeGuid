# 🎯 模糊音显示正确注音

> 💡 本功能通过自定义 Lua 过滤器实现，感谢 GitHub Copilot 的智能辅助。

当您启用模糊音后（例如 zh/z、ch/c、sh/s 不分），输入法虽然能够识别出您想要的词，但您可能会不记得这个词的正确读音。这时候，`say_it_right_filter` 可以在候选词旁边自动标注正确的拼音。

## 📋 功能说明

- **自动识别模糊音**：当您使用模糊音输入时，自动检测并标注正确读音
- **智能匹配**：支持完整拼音、模糊音和首字母简写三种匹配模式
- **可自定义样式**：支持配置标注格式、连接符等显示样式
- **友好兼容**：与 `corrector` 等其他过滤器兼容，不会产生冲突

## 📝 使用示例

例如，当您配置了 `chi → c` 的模糊音规则后：

- 输入 `ci fan`（使用了模糊音）
- 候选词显示：`吃饭 〔吃=chi 饭=fan〕`
- 这样您就知道"吃"的正确读音是 `chi` 而不是 `ci`

## 🔧 配置方法

### 1. 放置过滤器文件

将 `say_it_right_filter.lua` 文件放入用户文件夹的 `lua` 子目录中：

```
<用户文件夹>/
└── lua/
    └── say_it_right_filter.lua
```

### 2. 在输入方案中启用

在 `rime_ice.custom.yaml` 中添加以下配置：

```yaml
patch:
  # 启用 spelling_hints（必需，用于提供真实拼音）
  # 雾凇拼音（Rime-ice）中默认设置为8，可以不覆盖
  translator/spelling_hints: 8

  # 在 filters 中添加 say_it_right_filter
  # 注意：必须放在 spelling_hints 之后，在 corrector 之前
  engine/filters/@before 0:
    - lua_filter@*say_it_right_filter

  # 可选：自定义显示样式
  say_it_right_filter:
    style: "〔{pinyin}〕" # 注释外层样式
    single_char_format: "{pinyin}" # 单字格式
    multi_char_format: "{char}={pinyin}" # 多字格式
    separator: " " # 多个注释之间的连接符
    keep_original_comment: false # 是否保留原始拼音注释
```

您使用的皮肤可能没有针对comment做视觉优化，可以参考项目文件`weasel.custom.yaml`中的设置。

### 3. 重新部署

在输入法图标上右键，点击`重新部署（R）`，使配置生效。

## ⚙️ 配置选项详解

| 选项                    | 默认值             | 说明                                        |
| ----------------------- | ------------------ | ------------------------------------------- |
| `style`                 | `{pinyin}`         | 注释的外层样式，`{pinyin}` 为占位符         |
| `single_char_format`    | `{pinyin}`         | 单字的显示格式，可用 `{char}` 和 `{pinyin}` |
| `multi_char_format`     | `{char}({pinyin})` | 多字词的显示格式                            |
| `separator`             | ` `（空格）        | 多个模糊音标注之间的连接符                  |
| `keep_original_comment` | `false`            | 是否保留原始的拼音注释（兼容 corrector）    |

## 📌 注意事项

1. **依赖关系**：必须先启用 `translator/spelling_hints` 才能正常工作
2. **放置顺序**：在 filters 列表中必须放在 `spelling_hints` 之后，在 `corrector` 等修改 comment 的 filter 之前
3. **模糊音配置**：过滤器会自动读取您在 `speller/algebra` 中配置的模糊音规则（`derive` 类型）
4. **性能影响**：该过滤器对性能影响极小，可以放心使用

## 🔗 相关链接

- 功能讨论：[Mintimate/oh-my-rime#91](https://github.com/Mintimate/oh-my-rime/issues/91)
- 项目文件：`lua/say_it_right_filter.lua`
