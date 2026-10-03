# 忙碌消息助手 · Windows

Windows 版使用 Python、Tkinter、Windows UI Automation 与 DeepSeek API，在一段指定的忙碌时间内，为**一个明确选定且当前打开的个人微信私聊**生成 AI 回复。启动时先记住可见消息，已有消息不触发回复。新文字默认生成草稿，由用户确认；开启“生成后自动发送”后，只有微信窗口在前台、目标好友及消息未变、输入框为空时才尝试发送。

本版的范围刻意保持明确：不遍历好友列表，不处理群聊、公众号、图片、表情、语音、视频或收款等内容。微信版本的无障碍控件结构可能不同，首次运行必须根据本机微信填写控件选择器。本项目尚未在真实好友对话中完成端到端验证，不保证任意微信版本开箱即用。

## 文件结构

| 文件 | 作用 |
| --- | --- |
| `app.py` | Tkinter 界面、限时会话、草稿确认及自动发送流程 |
| `assistant/core.py` | 可见消息衔接、启动基线、回复轮数与发送回执规则 |
| `assistant/wechat.py` | pywinauto UIA 读取当前私聊及发送前后核对 |
| `assistant/deepseek.py` | DeepSeek Chat Completions 请求和回复检查 |
| `diagnose.py` | 列出微信可访问控件的类型、自动化 ID 和类名；不打印聊天正文 |
| `config.example.json` | 本机配置样例，不含密钥 |
| `tests/` | 不连接微信、不调用 API 的规则测试 |

## 环境与安装

- Windows 10/11，Python 3.11 或更新版本，已登录的 Windows 个人微信桌面版。
- 微信主聊天窗口保持打开、电脑唤醒并解锁，且 Windows UI Automation 能读取聊天界面。
- 微信需设置 **Enter 发送**。目前发送动作按一次 Enter；若微信使用 Ctrl+Enter，请先改回 Enter。
- 本人持有的 DeepSeek API Key。生成回复会将忙碌说明、目标好友的新文字发送到 DeepSeek；本版不上传图片或个人档案。

在 PowerShell 中从仓库根目录执行：

```powershell
cd Windows
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
Copy-Item config.example.json config.json
```

若 PowerShell 阻止激活脚本，可不激活，直接使用 `.\.venv\Scripts\python.exe` 运行后续命令。`config.json`、`.venv/` 和日志文件已被 `Windows/.gitignore` 排除，勿提交包含聊天内容的配置或输出。依赖在 [pywinauto 官方文档](https://pywinauto.readthedocs.io/en/latest/)中有 UIA 说明。

## 配置 DeepSeek Key

密钥**只从环境变量读取**，不写入配置文件或仓库：

```powershell
$env:DEEPSEEK_API_KEY = "你自己的密钥"
```

这只影响当前 PowerShell 会话。不要把真实密钥粘贴到公开终端记录、截图、Issue 或 PR。默认模型为 `deepseek-flash`，请求使用 DeepSeek 官方的 [Chat Completions API](https://api-docs.deepseek.com/api/create-chat-completion/)；可在 `config.json` 的 `model` 字段改为你的账号可用的模型。

## 找到本机微信控件

1. 打开微信主窗口，进入要回复的**一位好友的私聊**。不要把群聊当作测试对象。
2. 运行 `python diagnose.py`。它只列控件类型、`automation_id`、`class`、名称长度及窗口句柄，不输出好友名或聊天正文。这个输出仍可能包含你本机的软件结构，公开前请自行检查。
3. 在输出中确定四个**唯一**控件，并写进 `config.json` 的 `selectors`：当前聊天标题 `chat_title`、可见消息列表 `message_list`、消息输入框 `input`，以及只在一对一聊天出现的通话按钮 `direct_chat_marker`。每个选择器至少需有 `control_type` 和一个 `automation_id`、`class_name` 或 `name`，建议优先使用唯一的 `automation_id`。`name` 会包含实际可读文本，请勿把隐私信息提交到仓库。
4. 把 `contact` 改为当前聊天标题的**准确显示名**。`window_title_regex` 用于找到微信主窗口；若诊断显示标题长度为零，或标题随微信版本变化，需要调整本机窗口匹配方式；当前程序会拒绝在找不到唯一窗口时启动。

诊断树最多显示六层。若需要更深层，可在本机临时调大 `diagnose.py` 中的深度上限。若微信控件没有可区分的标识、消息正文不可读、或行内有多个文字标签而无法分辨正文，程序会跳过这些行；这种微信版本需要针对其 UIA 树适配，不能盲目自动发送。

`config.json` 还可设置：`activity`（当前忙碌说明）、`tone`（语气）、`duration_minutes`（5–480）、`max_replies`（1–100）和 `poll_seconds`。`config.example.json` 是带占位符的示例，不能直接运行。

## 使用

```powershell
python -m unittest discover -s tests -v
python app.py
```

1. 保持目标私聊打开，清空微信输入框，点击“开始”。此时建立消息基线，不处理旧消息。
2. 请一个获得同意的测试好友发**新的纯文字消息**。AI 草稿会显示在助手窗口；默认不会发送。
3. 草稿确认模式下，查看草稿后点击“5 秒后确认发送”，在倒计时内切回微信目标私聊。程序会再核对聊天、消息和空输入框，然后填写并按 Enter。若微信不在前台，不发送，草稿保留。
4. 确认本机读取方向和发送结果符合预期后，才勾选“生成后自动发送”。自动模式仍需微信窗口在前台；如果你切换聊天、自己输入文字或微信不可读取，程序会让行或暂停。
5. 点击“停止”或关闭程序即可结束。达到时长或轮数上限也会停止。运行中的草稿和聊天上下文只在内存中，关闭后不保留。

发送后必须在当前可见消息里看到对应的本人文字才算成功。若发送结果无法确认，会暂停本次会话，**不会重发**；请人工检查聊天记录和输入框。AI 请求失败也会暂停，以免在状态不明时继续。微信升级、锁屏、UIA 布局变化、聊天快速滚动、重复的相同文字，以及有人同时操作微信，都可能使消息判断失效。首次使用请只对同意测试的好友验证，并保持人工监督。

## 隐私与实现边界

- Key 只通过进程环境变量传入 HTTPS 请求；错误信息不包含 Key。源代码和示例配置无真实密钥。
- 未保存聊天日志、个人档案或 Key；界面仅展示本次草稿。DeepSeek 会接收新文字和忙碌说明。
- 只对当前目标私聊建立基线，不搜索历史会话。当前可见消息不能与上一份快照衔接时重新建立基线，避免把历史消息当作新消息。
- UIA 无法可靠确认发送时暂停，绝不自动再次按发送键。
- 本版不具备 Mac 端的“第一屏所有好友”、个人档案、话题持续追问和媒体提示功能；这些需要针对 Windows 微信的不同版本单独验证后扩展。
