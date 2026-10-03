import Cocoa
import SwiftUI

private let accent = Color(red: 0.16, green: 0.56, blue: 0.52)
struct Panel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    init(_ title: String, subtitle: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.045), lineWidth: 1))
    }
}
struct AssistantView: View {
    @ObservedObject var model: Assistant
    @State private var logFilter = "全部好友"
    @State private var showClearProfile = false
    @State private var showReplaceProfile = false
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版" }
    var profileSummary: String { model.profileEnabled && model.profileHasSavedContent ? "个人档案已启用" : "个人档案未启用" }
    var scopeSummary: String { model.scope == .all ? "所有好友 · 第一屏" : model.scope.rawValue }
    var toneDescription: String {
        ["自然简短": "用日常短句直接回应，轻松而克制。", "温柔友好": "语气温和，适当表达关心和理解。", "礼貌专业": "表达清楚、礼貌，适合正式沟通。", "轻松幽默": "适合时加入轻巧的幽默，不拿严肃话题开玩笑。", "俏皮活泼": "表达更灵动，可以有少量俏皮比喻和表情。"] [model.tone] ?? "根据你的表达偏好生成回复。"
    }
    var filteredLog: [LogItem] { model.log.filter { logFilter == "全部好友" || $0.contact == logFilter } }
    var currentActivity: ActivityPreset { ActivityPreset.all.first { $0.id == model.activityID } ?? ActivityPreset.all[0] }
    var logo: some View {
        Group {
            if let path = Bundle.main.path(forResource: "AppIconPreview", ofType: "png"), let image = NSImage(contentsOfFile: path) { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "bubble.left.and.bubble.right.fill").resizable().scaledToFit().foregroundStyle(accent) }
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 22)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch model.page {
                        case "回复设置": settings
                        case "个人档案": profile
                        case "会话记录": records
                        case "连接": connection
                        default: dashboard
                        }
                    }.padding(.horizontal, 32).padding(.bottom, 30)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        }.frame(minWidth: 950, minHeight: 730).tint(accent)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                logo.frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("忙碌助手").font(.system(size: 17, weight: .semibold))
                    Text("BUSY MATE").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(.top, 8)
            VStack(spacing: 7) {
                ForEach([("总览", "square.grid.2x2"), ("回复设置", "slider.horizontal.3"), ("个人档案", "person.text.rectangle"), ("会话记录", "text.bubble"), ("连接", "link")], id: \.0) { item in
                    Button { model.page = item.0 } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.1).frame(width: 20)
                            Text(item.0).font(.system(size: 14, weight: model.page == item.0 ? .semibold : .regular))
                            Spacer()
                        }.padding(.horizontal, 14).padding(.vertical, 13)
                            .foregroundStyle(model.page == item.0 ? accent : Color.primary.opacity(0.65))
                            .background(model.page == item.0 ? accent.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label(model.running ? "忙碌模式运行中" : "等待开启", systemImage: model.running ? "circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(model.running ? accent : .secondary)
                Text("把时间留给当下，\n消息由助手暂时接住。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                Text("本机助手 · \(appVersion)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
        }.padding(20).background(Color(nsColor: .controlBackgroundColor))
    }
    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.page == "总览" ? "你的忙碌时间" : model.page).font(.system(size: 28, weight: .bold))
                Text(["总览": "查看运行状态，开始一段专注时间。", "回复设置": "选择活动、回复对象，以及你喜欢的表达方式。", "个人档案": "告诉助手你是谁，让回复更贴合你的兴趣和表达。", "会话记录": "按好友查看收到的消息、AI 草稿和已发送回复。", "连接": "在本机管理 DeepSeek 连接与微信访问权限。"][model.page] ?? "")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.running ? accent : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Text(model.running ? "运行中" : "未运行").font(.system(size: 12, weight: .medium))
            }.padding(.horizontal, 12).padding(.vertical, 8).background(accent.opacity(0.08), in: Capsule())
        }
    }
    func metric(_ name: String, value: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(accent)
                .frame(width: 44, height: 44).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 19, weight: .semibold)); Text(name).font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(17).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
    }
    var dashboard: some View {
        Group {
            HStack(spacing: 12) {
                metric("\(model.running ? "剩余时间" : "计划时长")", value: model.running ? model.remaining : "\(model.minutes) 分钟", symbol: "clock")
                metric("已回复好友", value: "\(model.friendCount) 位", symbol: "person.2")
                metric("已发送回复", value: "\(model.rounds) 条", symbol: "paperplane")
            }
            Panel("本次忙碌计划") {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: currentActivity.icon).font(.system(size: 26)).foregroundStyle(accent)
                        .frame(width: 62, height: 62).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 19))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(currentActivity.title).font(.system(size: 21, weight: .semibold))
                        Text(model.activity).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("\(scopeSummary) · \(model.replyLimitSummary) · \(model.autoSend ? "自动发送" : "草稿确认")")
                            .font(.system(size: 12)).foregroundStyle(accent)
                    }
                    Spacer()
                    Button("编辑计划") { model.page = "回复设置" }.disabled(model.running)
                }
                HStack(spacing: 8) {
                    summaryChip(model.interaction.rawValue, symbol: model.interaction.icon)
                    summaryChip(model.expansion.rawValue, symbol: "bubble.left.and.bubble.right")
                    summaryChip(profileSummary, symbol: "person.text.rectangle")
                }
                Divider().opacity(0.6)
                HStack {
                    Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    if model.running { Button("立即停止") { model.stop() }.buttonStyle(.bordered).controlSize(.large) }
                    else { Button("开启忙碌模式") { model.start() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy) }
                }
            }
            if !model.draft.isEmpty {
                Panel("给 \(model.draftContact) 的回复草稿", subtitle: "确认后才会发送到该好友的微信。") {
                    Text("对方说：" + model.received).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(model.draft).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
                    HStack {
                        Button("确认发送") { model.confirmDraft() }.buttonStyle(.borderedProminent).disabled(!model.running || model.busy)
                        Button("忽略这次回复") { model.discardDraft() }.disabled(model.busy)
                    }
                }
            }
            Panel("最近动态", subtitle: "完整内容可在会话记录中查看。") {
                if model.log.isEmpty { Text("开启后，收到的消息和回复会出现在这里。").font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 15) }
                else { ForEach(Array(model.log.suffix(4).reversed())) { entry in logRow(entry, compact: true) } }
            }
        }
    }
    var settings: some View {
        Group {
            Panel("正在做什么", subtitle: "每种活动分别自动记住上次的说明，自定义状态也会保留。") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(ActivityPreset.all) { preset in
                        Button { model.chooseActivity(preset) } label: {
                            VStack(spacing: 9) { Image(systemName: preset.icon).font(.system(size: 20)); Text(preset.title).font(.system(size: 12, weight: .medium)) }
                                .frame(maxWidth: .infinity).frame(height: 72)
                                .foregroundStyle(model.activityID == preset.id ? accent : Color.secondary)
                                .background(model.activityID == preset.id ? accent.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(model.activityID == preset.id ? accent.opacity(0.4) : Color.clear))
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("告诉助手的当前状态").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { model.saveActivity() } label: { Label("保存当前状态", systemImage: "checkmark.circle") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                TextEditor(text: $model.activity).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 80)
                    .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityLabel("当前活动说明")
                Label(model.activitySaveStatus, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
            }
            Panel("回复对象", subtitle: "所有好友模式只检查聊天列表第一屏，按新的未读私聊依次处理。") {
                Picker("回复范围", selection: $model.scope) { ForEach(ReplyScope.allCases, id: \.self) { Text($0 == .all ? "所有好友（第一屏）" : $0.rawValue).tag($0) } }.pickerStyle(.segmented)
                if model.scope == .selected {
                    HStack { Label(model.contact.isEmpty ? "尚未选定好友" : model.contact, systemImage: "person.crop.circle"); Spacer(); Button("选定微信当前好友") { model.inspect() } }
                    Text("先在微信打开目标好友的聊天，再点击选定。切换到其他聊天后，仅从第一屏重新定位这位好友。").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Label("仅第一屏 · 排除群聊、公众号及第一屏内的同名会话", systemImage: "person.2.slash").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("启动时只为第一屏建立基线，已有未读消息不回复。之后只读取第一屏，不向下翻找；仅处理能核对为本次开始后到达的消息；历史时间、无法核对的时间及尚未加载的新消息不回复。首次进入第一屏的未读会话只检查最新一条。每位好友独立保存上下文，\(model.replyLimitSummary)。").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            sessionSettings
            Panel("与你一起使用电脑", subtitle: "默认开启后台处理，不抢到微信窗口。") {
                Label("使用其他应用时，助手在后台处理消息", systemImage: "macwindow.on.rectangle").font(.system(size: 13))
                Label("你在微信里浏览或输入时，助手先让行", systemImage: "hand.raised").font(.system(size: 13))
                Text("离开微信后会自动继续。微信有未发送文字时暂缓操作；检测到本人回复后，让行这位好友 60 秒。时间到、点击停止或关闭助手会结束忙碌模式。" + (model.unlimitedReplies ? "当前不限回复轮数，在本次时间内继续接话。" : "指定好友达到轮数上限也会结束。")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Panel("聊天互动", subtitle: "选择助手怎么接话，再决定是否顺势聊下去。") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(InteractionStyle.allCases, id: \.self) { style in interactionOption(style) }
                }
                Divider().opacity(0.6)
                Text("话题拓展").font(.system(size: 12, weight: .medium))
                Picker("话题拓展", selection: $model.expansion) {
                    ForEach(ConversationExpansion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Text(model.expansion.description).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.expansion == .continuous {
                    Label("每次回复主动接一个相关问题，发出前会检查是否有追问。", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 12)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
                }
                Text("遇到严肃、紧急的话题会认真回应；对方想结束聊天时不追问。拓展仍由对方的新消息触发，不会自行连续发消息。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Panel("表达与发送", subtitle: "DeepSeek 会结合新消息、聊天上下文和你启用的个人档案回答。") {
                Picker("表达风格", selection: $model.tone) {
                    ForEach(["自然简短", "温柔友好", "礼貌专业", "轻松幽默", "俏皮活泼"], id: \.self) { Text($0) }
                }.pickerStyle(.menu).frame(maxWidth: 280, alignment: .leading)
                Text(toneDescription).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("补充偏好（可选）").font(.system(size: 12, weight: .medium))
                TextField("例如：喜欢音乐话题；偶尔接一个轻松的梗；不要使用表情。", text: $model.instructions, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                HStack(spacing: 10) {
                    Image(systemName: "person.text.rectangle").foregroundStyle(accent)
                    Text(profileSummary).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("管理个人档案") { model.page = "个人档案" }
                }.padding(12).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                Toggle("生成后自动发送", isOn: $model.autoSend).toggleStyle(.switch)
                Text(model.autoSend ? "开启后，新文字消息将由 AI 直接回复，并保存记录。" : "当前为草稿确认模式，每次由你确认后发送。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.disabled(model.running || model.busy)
    }
    func durationLabel(_ minutes: Int) -> String {
        minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
    }
    func quickChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(selected ? accent : Color.secondary)
                .background(selected ? accent.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent.opacity(0.35) : Color.clear))
        }.buttonStyle(.plain).accessibilityValue(selected ? "已选中" : "未选中")
    }
    var sessionSettings: some View {
        Panel("持续时间与回复上限", subtitle: "直接选择常用值，或拖动滑块微调；不限轮数也会在计划时间结束时停止。") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("持续时间", systemImage: "clock").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("持续时间", selection: $model.minutes) {
                        ForEach(SessionChoices.minuteOptions(for: model.minutes), id: \.self) { value in Text(durationLabel(value)).tag(value) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 145)
                }
                HStack(spacing: 9) {
                    ForEach([15, 30, 60, 120], id: \.self) { value in
                        quickChoice(durationLabel(value), selected: model.minutes == value) { model.minutes = value }
                    }
                }
                Slider(value: Binding(get: { Double(model.minutes) }, set: { model.minutes = Int($0.rounded()) }), in: 5...480, step: 5)
                    .accessibilityLabel("持续时间滑块").accessibilityValue("\(model.minutes) 分钟")
                HStack { Text("5 分钟"); Spacer(); Text("8 小时") }.font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("每位好友的回复轮数", systemImage: "bubble.left.and.bubble.right").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("不限轮数", isOn: $model.unlimitedReplies).toggleStyle(.switch).fixedSize()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("最多回复").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Picker("每位好友最多回复", selection: $model.limit) {
                            ForEach(SessionChoices.roundOptions(for: model.limit), id: \.self) { value in Text("\(value) 轮").tag(value) }
                        }.labelsHidden().pickerStyle(.menu).frame(width: 145)
                    }
                    HStack(spacing: 9) {
                        ForEach([5, 10, 20, 50], id: \.self) { value in
                            quickChoice("\(value) 轮", selected: model.limit == value) { model.limit = value }
                        }
                    }
                    Slider(value: Binding(get: { Double(model.limit) }, set: { model.limit = Int($0.rounded()) }), in: 1...100, step: 1)
                        .accessibilityLabel("回复轮数滑块").accessibilityValue("\(model.limit) 轮")
                    HStack { Text("1 轮"); Spacer(); Text("100 轮") }.font(.system(size: 10)).foregroundStyle(.tertiary)
                }.disabled(model.unlimitedReplies).opacity(model.unlimitedReplies ? 0.45 : 1)
                Text(model.unlimitedReplies ? "在本次忙碌时间内不限轮数。关闭后恢复最多 \(model.limit) 轮的设置。" : "每位好友最多回复 \(model.limit) 轮；一轮指助手发出一条回复。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    func summaryChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent).padding(.horizontal, 10).padding(.vertical, 7)
            .background(accent.opacity(0.065), in: Capsule())
    }
    func interactionOption(_ style: InteractionStyle) -> some View {
        Button { model.interaction = style } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: style.icon).font(.system(size: 19))
                    Spacer()
                    Image(systemName: model.interaction == style ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14)).opacity(model.interaction == style ? 1 : 0.3)
                }
                Text(style.rawValue).font(.system(size: 13, weight: .semibold))
                Text(style.description).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                Spacer(minLength: 0)
            }.padding(15).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                .foregroundStyle(model.interaction == style ? accent : Color.primary.opacity(0.7))
                .background(model.interaction == style ? accent.opacity(0.10) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(model.interaction == style ? accent.opacity(0.35) : Color.clear))
        }.buttonStyle(.plain).accessibilityLabel(style.rawValue).accessibilityValue(model.interaction == style ? "已选中" : "未选中")
    }
    var profile: some View {
        Group {
            if model.running {
                Label("忙碌模式使用开启时的已保存档案；停止后可以编辑。", systemImage: "lock")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Panel("给助手一点关于你的背景", subtitle: "简介、兴趣和说话习惯能让接话更自然。先整理愿意让回复对象知道的内容，再决定是否启用。") {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "person.crop.rectangle.stack").font(.system(size: 25)).foregroundStyle(accent)
                        .frame(width: 56, height: 56).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.profileHasSavedContent ? "已保存个人档案" : "创建你的个人档案").font(.system(size: 16, weight: .semibold))
                        Text(model.profileSourceName.isEmpty ? "可以导入 Markdown 简介，或直接在下方填写。" : "来源：" + model.profileSourceName)
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        if let date = model.profileUpdatedAt {
                            Text("上次保存：" + date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 10)
                    Button {
                        if model.profileIsDirty { showReplaceProfile = true }
                        else { model.importProfile() }
                    } label: { Label("导入 .md 简介", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                Divider().opacity(0.6)
                Toggle("回复时使用已保存的个人档案", isOn: $model.profileEnabled)
                    .toggleStyle(.switch).disabled(!model.profileHasSavedContent)
                Text(model.profileEnabled && model.profileHasSavedContent ? "启用后，已保存简介会与所选范围内的好友消息一起发送给 DeepSeek，用于生成更贴合你的回复。" : "档案保存在本机。导入和编辑不会自动启用；开启后才会在生成回复时使用。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(model.running || model.busy)
            Panel("个人简介", subtitle: "可以写昵称、日常兴趣、聊天偏好，以及助手可以回答或需要交给你的事情。") {
                HStack {
                    Text("Markdown 内容").font(.system(size: 12, weight: .medium))
                    Spacer()
                    if model.profileIsDirty {
                        Label("有未保存修改", systemImage: "circle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    Text("\(model.profileCharacterCount) / \(PersonalProfile.maxCharacters) 字")
                        .font(.system(size: 11)).foregroundStyle(model.profileCharacterCount > PersonalProfile.maxCharacters ? Color.red : Color.secondary)
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.profileText).font(.system(size: 14)).lineSpacing(5)
                        .scrollContentBackground(.hidden).padding(9).accessibilityLabel("个人简介编辑框")
                    if model.profileText.isEmpty {
                        Text("# 关于我\n\n喜欢什么、平时怎么聊天、哪些事情需要本人决定……")
                            .font(.system(size: 14)).lineSpacing(5).foregroundStyle(.tertiary)
                            .padding(14).allowsHitTesting(false)
                    }
                }.frame(height: 285).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
                HStack(spacing: 10) {
                    Button("保存档案") { model.saveProfile() }.buttonStyle(.borderedProminent)
                        .disabled(!model.profileIsDirty || model.profileText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.profileCharacterCount > PersonalProfile.maxCharacters)
                    Button("清空档案", role: .destructive) { showClearProfile = true }
                        .disabled(!model.profileHasSavedContent && model.profileText.isEmpty)
                    Spacer()
                }
                if !model.profileStatus.isEmpty {
                    Text(model.profileStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Text(model.profileIsDirty ? "未保存的修改不会用于回复；保存后，启用的档案才会使用新内容。" : "简介只作为背景信息。助手不会据此冒充本人，或替你承诺时间、金钱和重要决定。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(model.running || model.busy)
        }
        .confirmationDialog("清空个人档案？", isPresented: $showClearProfile, titleVisibility: .visible) {
            Button("清空档案并停用", role: .destructive) { model.clearProfile() }
            Button("取消", role: .cancel) { }
        } message: { Text("会移除已保存的简介和当前编辑内容。原来的 Markdown 文件不会被修改。") }
        .confirmationDialog("替换当前编辑内容？", isPresented: $showReplaceProfile, titleVisibility: .visible) {
            Button("选择新的 .md 简介") { model.importProfile() }
            Button("取消", role: .cancel) { }
        } message: { Text("导入成功后会保存新简介，并替换未保存的修改。") }
    }
    func logRow(_ item: LogItem, compact: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind == "已发送" ? "paperplane.fill" : item.kind == "收到消息" ? "bubble.left.fill" : "circle.dotted")
                .foregroundStyle(accent).frame(width: 28, height: 28).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(item.contact.isEmpty ? item.kind : item.contact + " · " + item.kind).font(.system(size: 12, weight: .semibold)); Spacer(); Text(item.time.formatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary) }
                Text(item.content).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(compact ? 2 : nil).textSelection(.enabled)
            }
        }.padding(.vertical, 5)
    }
    var records: some View {
        Panel("会话时间线", subtitle: "聊天记录保存在本机，可打开原始记录文件。") {
            HStack {
                Picker("好友", selection: $logFilter) {
                    Text("全部好友").tag("全部好友")
                    ForEach(Array(Set(model.log.map(\.contact).filter { !$0.isEmpty })).sorted(), id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 220)
                Text("\(filteredLog.count) 条记录").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(); Button("打开记录文件") { model.revealLogs() }.disabled(model.log.isEmpty)
            }
            if model.log.isEmpty { Label("还没有会话记录", systemImage: "tray").foregroundStyle(.secondary).padding(.vertical, 50).frame(maxWidth: .infinity) }
            else { ForEach(filteredLog.reversed()) { item in logRow(item); Divider().opacity(0.5) } }
        }
    }
    var connection: some View {
        Group {
            Panel("DeepSeek", subtitle: "密钥只在本机填写；保存时使用 macOS 钥匙串。") {
                SecureField("API 密钥", text: $model.key).textFieldStyle(.roundedBorder)
                HStack { Button("保存密钥") { model.saveKey() }; Button("测试连接") { model.testConnection() }; Spacer(); Text(model.connectionStatus).font(.system(size: 12)).foregroundStyle(.secondary) }
                TextField("模型", text: $model.modelName).textFieldStyle(.roundedBorder)
                Text("连接测试只发送测试文字，不包含微信消息；会使用少量 API 额度。").font(.system(size: 12)).foregroundStyle(.secondary)
            }.disabled(model.running || model.busy)
            Panel("微信与设备", subtitle: "使用 macOS 辅助功能读取文字消息，并操作微信界面。") {
                Label("辅助功能权限", systemImage: "hand.raised").font(.system(size: 14, weight: .medium))
                Text("系统设置 → 隐私与安全性 → 辅助功能 → 开启本应用。更新后若权限失效，请重新添加并重启应用。").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack {
                    Button("检查第一屏") { model.testChatList() }.disabled(model.running || model.busy)
                    Text(model.scanStatus).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("只读取聊天列表第一屏，显示本次可识别的会话数量；不向下滚动查找。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("检查后台操作") { model.testBackground() }.disabled(model.running || model.busy)
                    Text(model.backgroundStatus).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("检查回车发送（仅文件传输助手）") { model.testReturnSending() }.disabled(model.running || model.busy)
                    Text(model.returnCheckStatus).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("后台检查只在第一屏选择已读会话进行切换与还原，短暂填写检查文字后清除；不调用 AI，不发送消息。").font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Text("保持 Mac 唤醒、解锁，微信登录并保留主聊天窗口；它可以被其他应用遮住。文字使用 DeepSeek；新图片和表情包仅回复固定提示，不识别画面；视频和语音不自动回复。").font(.system(size: 13)).foregroundStyle(.secondary)
                Text("开启忙碌模式后，所选范围内的新文字、最近几轮上下文，以及你启用的已保存个人档案会发送给 DeepSeek 生成回复。").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
