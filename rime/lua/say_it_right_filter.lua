-- 模糊音正确注音过滤器
-- 功能：当使用模糊音输入时，在候选词上标注正确的拼音
-- 相关讨论：https://github.com/Mintimate/oh-my-rime/issues/91
--
-- 依赖：需要启用 translator/spelling_hints（它会在 comment 中显示真实拼音）
-- 放置顺序：必须在 spelling_hints 之后，在 corrector 等修改 comment 的 filter 之前
--
-- 支持的匹配类型：
--   1. 完整拼音匹配（chi fan → 吃饭）
--   2. 模糊音匹配（ci fan → 吃饭，标注〔吃=chi〕）
--   3. 首字母简写（cfl → 吃饭了，不标注）
--
-- 配置选项（在 custom.yaml 中配置）：
--   say_it_right_filter:
--     style: "〔{pinyin}〕"                # 注释外层样式，{pinyin} 为占位符
--     single_char_format: "{pinyin}"      # 单字格式（可用占位符：{char} {pinyin}）
--     multi_char_format: "{char}={pinyin}" # 多字格式（可用占位符：{char} {pinyin}）
--     separator: " "                       # 多个注释之间的连接符（如：吃=chi 饭=fan）
--     keep_original_comment: true          # 保留原始拼音注释（兼容 corrector）
--
-- 工作机制：
--   - 有模糊音时：只显示模糊音提示（优先级高于 corrector）
--   - 无模糊音但输入不匹配时：保留原始注释供 corrector 处理错音
--   - 完全匹配时：根据 keep_original_comment 决定是否保留注释

local M = {}

-- ============================================================================
-- 辅助工具函数
-- ============================================================================

-- 解析配置中的模糊音规则（derive 类型）
local function parse_fuzzy_rules(config)
    local rules = {}
    local algebra = config:get_list('speller/algebra')

    if not algebra then
        return rules
    end

    for i = 0, algebra.size - 1 do
        local rule = algebra:get_value_at(i).value
        if rule then
            -- 解析形如 derive/pattern/replacement/ 的规则
            local pattern, replacement = rule:match("^derive/(.-)/(.-)/")
            if pattern and replacement then
                table.insert(rules, {
                    pattern = pattern,
                    replacement = replacement:gsub("%$(%d)", "%%%1"), -- $1 → %1
                    original_rule = rule
                })
            end
        end
    end

    return rules
end

-- 分割拼音字符串为音节数组
local function split_pinyin(pinyin_str)
    local result = {}
    for syllable in pinyin_str:gmatch("[^ ]+") do
        table.insert(result, syllable)
    end
    return result
end

-- ============================================================================
-- 初始化：读取配置和模糊音规则
-- ============================================================================

function M.init(env)
    local config = env.engine.schema.config
    env.name_space = env.name_space:gsub('^*', '')

    -- 读取用户配置
    env.keep_original_comment = config:get_bool(env.name_space .. '/keep_original_comment')

    -- 获取拼音分隔符（如果有）
    local delimiter = config:get_string('speller/delimiter')
    if delimiter and #delimiter > 0 and delimiter:sub(1, 1) ~= ' ' then
        env.delimiter = delimiter:sub(1, 1)
    end

    -- 注释显示样式配置
    M.style = config:get_string(env.name_space .. '/style') or '{pinyin}'

    -- 单字和多字的格式模板（支持 {char} 和 {pinyin} 占位符）
    M.single_char_format = config:get_string(env.name_space .. '/single_char_format') or '{pinyin}'
    M.multi_char_format = config:get_string(env.name_space .. '/multi_char_format') or '{char}({pinyin})'
    -- 多个注释之间的连接符
    M.separator = config:get_string(env.name_space .. '/separator') or ' ' -- 默认使用空格

    -- 从 speller/algebra 中提取模糊音规则
    M.fuzzy_rules = parse_fuzzy_rules(config)
end

-- ============================================================================
-- 匹配逻辑：判断输入和真实拼音的关系
-- ============================================================================

-- 检查两个音节是否通过模糊音规则匹配
-- 返回 true 表示 input_syl 是 real_syl 的模糊音变体
local function is_fuzzy_match(input_syl, real_syl)
    if input_syl == real_syl or not M.fuzzy_rules or #M.fuzzy_rules == 0 then
        return false
    end

    -- 遍历所有模糊音规则，检查 real_syl 能否通过规则变成 input_syl
    for _, rule in ipairs(M.fuzzy_rules) do
        local transformed = real_syl:gsub(rule.pattern, rule.replacement)
        if transformed ~= real_syl and transformed == input_syl then
            return true -- 找到匹配的模糊音规则
        end
    end

    return false
end

-- 尝试匹配单个音节，返回最佳匹配结果
-- 返回：match_info { syllable, length, type } 或 nil
local function try_match_syllable(input, pos, real_syl)
    local input_len = #input
    local real_len = #real_syl
    local best_match = nil

    -- 策略1：尝试完整匹配（优先级最高）
    if pos + real_len - 1 <= input_len then
        local input_syl = input:sub(pos, pos + real_len - 1)
        if input_syl == real_syl then
            return { syllable = input_syl, length = real_len, type = "exact" }
        end
    end

    -- 策略2：尝试模糊音匹配（允许长度差异 ±2）
    for try_len = math.max(1, real_len - 2), math.min(input_len - pos + 1, real_len + 2) do
        if pos + try_len - 1 > input_len then
            break
        end

        local input_syl = input:sub(pos, pos + try_len - 1)
        if is_fuzzy_match(input_syl, real_syl) then
            -- 优先选择长度最接近的模糊匹配
            if not best_match or math.abs(try_len - real_len) < math.abs(best_match.length - real_len) then
                best_match = { syllable = input_syl, length = try_len, type = "fuzzy" }
            end
        end
    end

    if best_match then
        return best_match
    end

    -- 策略3：尝试首字母简写
    local first_char = real_syl:sub(1, 1)
    if pos <= input_len and input:sub(pos, pos) == first_char then
        return { syllable = first_char, length = 1, type = "initial" }
    end

    return nil -- 无法匹配
end

-- 将输入映射到真实音节序列
-- 返回：matched[] 或 nil（匹配失败）
local function match_input_syllables(input_code, real_syllables)
    local normalized_input = input_code:gsub("[ ']", "") -- 移除空格和单引号
    local input_len = #normalized_input

    if #real_syllables == 0 then
        return nil
    end

    -- 贪婪匹配：从左到右逐个匹配音节
    local pos = 1
    local matched = {}

    for i, real_syl in ipairs(real_syllables) do
        local match_info = try_match_syllable(normalized_input, pos, real_syl)

        if not match_info then
            return nil -- 无法匹配当前音节，整体匹配失败
        end

        table.insert(matched, {
            input = match_info.syllable,
            real = real_syl,
            index = i,
            is_fuzzy = (match_info.type == "fuzzy"),
            match_type = match_info.type
        })

        pos = pos + match_info.length
    end

    -- 检查是否完全消耗了输入
    return (pos - 1 == input_len) and matched or nil
end

-- ============================================================================
-- 主过滤函数
-- ============================================================================

-- 从 comment 中提取拼音（由 spelling_hints 生成，格式：［chi fan］）
local function extract_pinyin(comment, delimiter)
    local pinyin = comment:match("^［(.-)］$")
    if not pinyin or #pinyin == 0 then
        return nil
    end

    -- 将分隔符替换为空格
    if delimiter then
        pinyin = pinyin:gsub(delimiter, ' ')
    end

    return pinyin
end

-- 生成模糊音标注文本
local function generate_annotation(matched, cand_text)
    local fuzzy_parts = {}
    local seen = {} -- 用于去重
    local char_index = 0
    local total_chars = 0

    -- 先统计总字符数
    for _ in utf8.codes(cand_text) do
        total_chars = total_chars + 1
    end

    -- 判断是否为单字
    local is_single_char = (total_chars == 1)

    for _, code in utf8.codes(cand_text) do
        char_index = char_index + 1
        local char = utf8.char(code)

        -- 只标注使用了模糊音的字
        if matched[char_index] and matched[char_index].is_fuzzy then
            local pinyin = matched[char_index].real
            local annotation

            -- 根据配置的格式模板生成注释
            if is_single_char then
                annotation = M.single_char_format:gsub('{char}', char):gsub('{pinyin}', pinyin)
            else
                annotation = M.multi_char_format:gsub('{char}', char):gsub('{pinyin}', pinyin)
            end

            -- 避免重复显示相同的注释
            if not seen[annotation] then
                table.insert(fuzzy_parts, annotation)
                seen[annotation] = true
            end
        end
    end

    if #fuzzy_parts > 0 then
        return table.concat(fuzzy_parts, M.separator)
    end

    return nil
end

-- 处理单个候选词
local function process_candidate(cand, input_code, env)
    local original_comment = cand.comment -- 保存原始comment

    -- 提取真实拼音
    local real_pinyin = extract_pinyin(cand.comment, env.delimiter)
    if not real_pinyin then
        return -- 没有拼音信息，保持原样
    end

    -- 规范化比较
    local normalized_input = input_code:gsub("[ ']", "")
    local normalized_pinyin = real_pinyin:gsub(" ", "")

    -- 完全匹配时的处理
    if normalized_input == normalized_pinyin then
        if not env.keep_original_comment then
            cand:get_genuine().comment = ""
        end
        -- keep_original_comment 为 true 时保持原样，供 corrector 处理
        return
    end

    -- 尝试匹配输入和真实拼音
    local real_syllables = split_pinyin(real_pinyin)
    local matched = match_input_syllables(input_code, real_syllables)

    if matched then
        -- 生成模糊音标注
        local annotation = generate_annotation(matched, cand.text)
        if annotation then
            -- 有模糊音：显示模糊音提示（优先级高于 corrector）
            cand:get_genuine().comment = M.style:gsub('{pinyin}', annotation)
        else
            -- 无模糊音但输入不完全匹配：保留原始注释供 corrector 处理
            if not env.keep_original_comment then
                cand:get_genuine().comment = ""
            end
            -- keep_original_comment 为 true 时保持原样
        end
    else
        -- 匹配失败（可能是错音）：保留原始注释供 corrector 处理
        if not env.keep_original_comment then
            cand:get_genuine().comment = ""
        end
        -- keep_original_comment 为 true 时保持原样
    end
end

function M.func(input, env)
    local input_code = env.engine.context.input

    -- 无输入时直接透传
    if not input_code or #input_code == 0 then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    -- 处理每个候选词
    for cand in input:iter() do
        process_candidate(cand, input_code, env)
        yield(cand)
    end
end

return M
