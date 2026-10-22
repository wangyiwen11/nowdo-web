import SwiftUI
import AppKit
import NowDoCore

extension Color {
    static let ink = Color(red: 0.18, green: 0.13, blue: 0.24)
    static let grape = Color(red: 0.45, green: 0.26, blue: 0.76)
    static let lavender = Color(red: 0.95, green: 0.93, blue: 0.98)
    static let paper = Color(red: 0.985, green: 0.98, blue: 0.995)
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calendar: CalendarBridge
    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.grape.opacity(0.2)).frame(width: 34, height: 4).padding(.top, 10).padding(.bottom, 12)
            HStack(alignment: .center) {
                ZStack { RoundedRectangle(cornerRadius: 11).fill(Color.grape).frame(width: 36, height: 36)
                    Image(systemName: "pause.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("NowDo · 计时点").font(.system(size: 17, weight: .semibold))
                    Text("点一下，记住时间花在哪。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.onCollapse?() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).help("收成悬浮小点，计时继续")
            }.padding(.horizontal, 22).padding(.bottom, 18)

            if let quickStart = model.quickStart {
                CalendarDropTarget(quickStart: quickStart).frame(height: 38).padding(.horizontal, 20).padding(.bottom, 4)
            }

            if model.demo {
                HStack { Label("示例体验 · 不保存到正式记录", systemImage: "sparkles").font(.system(size: 11))
                    Spacer(); Button("结束体验") { model.leaveDemo() }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                }.foregroundStyle(Color.grape).padding(10).background(Color.lavender)
            }
            if let failure = model.failure {
                Label(failure, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.red)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.05))
            }
            if let message = model.message {
                HStack(alignment: .top) { Text(message).font(.system(size: 11)); Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(10).foregroundStyle(Color.grape).background(Color.lavender)
            }
            HStack(spacing: 4) {
                tabButton("事项", icon: "circle.grid.2x2", value: 0)
                tabButton("复盘", icon: "chart.bar.xaxis", value: 1)
                tabButton("设置", icon: "slider.horizontal.3", value: 2)
            }.padding(4).background(Color.lavender, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 20).padding(.vertical, 14)
            if model.tab != 2 { dayPicker.padding(.horizontal, 22).padding(.bottom, 14) }
            GeometryReader { space in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.tab == 0 { taskContent }
                        else if model.tab == 1 { ReviewView(model: model) }
                        else { SettingsView(model: model, calendar: calendar) }
                    }.padding(.horizontal, 20).padding(.bottom, 24)
                }.frame(width: space.size.width, height: space.size.height)
            }
            HStack(spacing: 6) {
                Circle().fill(model.isRunning ? Color.grape : Color.gray.opacity(0.5)).frame(width: 5, height: 5)
                Text(model.isRunning ? "正在记录 · 切换事项自动暂停上一件" : "记录留在这台 Mac · 无需登录").font(.system(size: 10))
                Spacer()
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 12)
                .background(Color.white)
        }
        .foregroundStyle(Color.ink).background(Color.paper)
        .preferredColorScheme(.light)
        .tint(.grape)
        .frame(width: 420, height: 700)
    }

    func tabButton(_ title: String, icon: String, value: Int) -> some View {
        Button { model.tab = value } label: {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(model.tab == value ? Color.grape : Color.secondary)
                .background(model.tab == value ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityAddTraits(model.tab == value ? .isSelected : [])
    }
    var dayPicker: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Calendar.current.isDateInToday(model.day) ? "今天" : model.day.formatted(.dateTime.month().day()))
                    .font(.system(size: 20, weight: .semibold))
                Text(model.day.formatted(.dateTime.month().day().weekday(.wide))).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.shiftDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }.help("前一天")
            Button("今天") { model.today() }.font(.system(size: 11))
            Button { model.shiftDay(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }.help("后一天")
        }.buttonStyle(.plain)
    }
    @ViewBuilder var taskContent: some View {
        if model.current != nil { FocusCard(model: model) }
        if !calendar.allowed && !model.demo {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 26)).foregroundStyle(Color.grape)
                Text("日历已经排好了，\n现在只管开始。").font(.system(size: 23, weight: .semibold)).lineSpacing(4)
                Text("直接把苹果日历中的事项拖到上方，松手即开始。也可以连接日历，在这里查看日程。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                Button(calendar.loading ? "正在连接…" : "连接苹果日历") { calendar.connect() }
                    .buttonStyle(PurpleButton()).disabled(calendar.loading)
                if let error = calendar.error { Text(error).font(.system(size: 11)).foregroundStyle(.secondary) }
                if calendar.status == .denied || calendar.status == .restricted || calendar.status == .writeOnly {
                    Button("前往系统设置，允许日历访问") { openCalendarSettings() }.font(.system(size: 11)).buttonStyle(.plain)
                }
                Button("先用示例试试 →") { model.enterDemo() }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.grape)
                Text("系统会要求完整日历权限；本工具只读取，不改动原日程。提醒事项暂未接入。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 18))
        }
        if calendar.allowed || model.demo || !model.ledger.state.items.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("找一件事…", text: $model.query).textFieldStyle(.plain)
            }.font(.system(size: 12)).padding(11).background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        if calendar.allowed || model.demo {
            HStack {
                Text("日历里的事").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { calendar.date = model.day; calendar.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新日历").disabled(model.demo)
            }
            if model.displayItems.isEmpty {
                Text(model.query.isEmpty ? "这天没有可见日程。可在日历里创建，或在下面记一件临时事项。" : "没有找到匹配的事项。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            VStack(spacing: 8) { ForEach(model.displayItems) { item in EventRow(model: model, item: item) } }
        }
        if !model.previousItems.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("随时接着做").font(.system(size: 13, weight: .semibold))
                Text("记录过的事项会留在这里，跨天也能找到。").font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(model.previousItems.prefix(8)) { item in EventRow(model: model, item: item) }
                if model.previousItems.count > 8 { Text("用上方搜索查找其他历史事项。").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
        DisclosureGroup(isExpanded: $model.showQuick) {
            VStack(spacing: 10) {
                TextField("临时想做什么？", text: $model.quickTitle).textFieldStyle(.roundedBorder).onSubmit { model.addQuick() }
                HStack { TextField("计划分钟数（可留空）", text: $model.quickMinutes).textFieldStyle(.roundedBorder)
                    Button("开始") { model.addQuick() }.buttonStyle(.borderedProminent).disabled(model.quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.readOnly) }
                Text("只在计时点中记录，不创建或修改日历。").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.top, 10)
        } label: { Label("加一件临时事项", systemImage: "plus").font(.system(size: 12, weight: .medium)) }
    }
}

struct FocusCard: View {
    @ObservedObject var model: AppModel
    @State var note = ""
    @State var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.isRunning ? "正在做" : "停下来也没关系", systemImage: model.isRunning ? "smallcircle.filled.circle" : "pause.circle")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Button { model.onCollapse?() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .buttonStyle(.plain).help("收成悬浮点")
            }
            Text(model.current?.title ?? "").font(.system(size: 16, weight: .semibold)).lineLimit(2)
            HStack(alignment: .firstTextBaseline) {
                Text(timerText(model.currentSeconds)).font(.system(size: 38, weight: .light, design: .rounded)).monospacedDigit()
                Text("累计用时").font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Button { model.toggle() } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
                        .foregroundStyle(Color.grape).background(.white, in: Circle())
                }.buttonStyle(.plain).help(model.isRunning ? "暂停计时" : "继续计时").disabled(model.readOnly)
            }
            if !model.currentNote.isEmpty {
                Label(model.currentNote, systemImage: "arrow.turn.down.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
            }
            if let item = model.current, let plan = item.plannedDuration, model.currentSeconds > plan && model.isRunning {
                Text("已超过原计划。还在做就继续，忘记暂停可去复盘修正。").font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
            }
            if !model.isRunning, let session = model.ledger.state.sessions.last(where: { $0.itemID == model.current?.id }) {
                if editing {
                    HStack {
                        TextField("做到哪了？下一步是什么？", text: $note).textFieldStyle(.roundedBorder).foregroundStyle(Color.ink)
                        Button("记下") { model.saveNote(note, session: session); if model.failure == nil { editing = false } }.buttonStyle(.plain)
                    }.font(.system(size: 11))
                } else {
                    Button { note = session.note; editing = true } label: { Label("留一句进度（可选）", systemImage: "square.and.pencil") }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }.padding(20).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color.grape, Color(red: 0.34, green: 0.20, blue: 0.59)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 19))
            .onChange(of: model.current?.id) { _, _ in editing = false }
    }
}

struct EventRow: View {
    @ObservedObject var model: AppModel
    let item: WorkItem
    var running: Bool { model.ledger.activeItemID == item.id }
    var body: some View {
        Button { if running { model.pause() } else { model.start(item) } } label: {
            HStack(spacing: 12) {
                Image(systemName: running ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(running ? Color.white : Color.grape).frame(width: 33, height: 33)
                    .background(running ? Color.grape : Color.lavender, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    HStack(spacing: 5) {
                        Text(item.isAllDay ? "全天" : item.plannedStart?.formatted(date: .omitted, time: .shortened) ?? "随时")
                        Text("·")
                        Text(item.calendarName).lineLimit(1)
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 3)
                VStack(alignment: .trailing, spacing: 5) {
                    if model.allTime(item) > 0 { Text(minuteText(model.allTime(item))).foregroundStyle(Color.grape) }
                    if let planned = item.plannedDuration { Text("计划 \(Int(planned / 60)) 分") }
                    else { Text("不设时长") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(running ? Color.grape.opacity(0.45) : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain).disabled(model.readOnly).help(running ? "暂停这件事" : "开始这件事，自动暂停上一件")
    }
}

struct ReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("时间花在了哪里").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(minuteText(model.total)).font(.system(size: 30, weight: .light, design: .rounded))
                    Text("\(model.reviewItems.count) 件事 · 手动计时，不判断效率高低").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis").font(.system(size: 26)).foregroundStyle(Color.grape.opacity(0.7))
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.lavender, in: RoundedRectangle(cornerRadius: 17))
            if model.reviewItems.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("先做一小段，再来看。").font(.system(size: 17, weight: .medium))
                    Text("开始一件事后，实际用时会出现在这里。全天事项只显示用时，不拿一天来做比较。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                    Button("去选一件事 →") { model.tab = 0 }.buttonStyle(.plain).foregroundStyle(Color.grape)
                }.padding(.vertical, 10)
            } else {
                ForEach(model.reviewItems) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top) { Text(item.title).font(.system(size: 13, weight: .medium)); Spacer()
                            Text(minuteText(model.seconds(item))).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.grape) }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.lavender)
                                Capsule().fill(Color.grape.opacity(0.75)).frame(width: max(4, proxy.size.width * model.seconds(item) / max(model.total, 1)))
                            }
                        }.frame(height: 5)
                        if let plan = item.plannedDuration {
                            let diff = model.allTime(item) - plan
                            Text("计划 \(minuteText(plan)) · 累计 \(minuteText(model.allTime(item))) · \(diff >= 0 ? "多用" : "还余") \(minuteText(abs(diff)))")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        } else { Text("未设计划时长 · 这次用时可作为下次参考").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 13))
                }
                HStack { Text("每一段记录").font(.system(size: 13, weight: .semibold)); Spacer()
                    Button("导出当天") { model.exportCSV() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.grape) }
                ForEach(model.sessions) { session in SessionRow(model: model, session: session) }
                Text("计划来自开始计时时的日程。实际用时按所选日期拆分，跨天事项的计划对比使用累计用时。计时代表你记录的经过时间。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }
}

struct SessionRow: View {
    @ObservedObject var model: AppModel
    let session: TimeSession
    @State private var editing = false
    @State private var note = ""
    @State private var end = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.itemTitle(session.itemID)).font(.system(size: 12, weight: .medium))
                    Text("\(session.start.formatted(date: .omitted, time: .standard)) → \(session.end?.formatted(date: .omitted, time: .standard) ?? "计时中")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if session.end != nil {
                    Button(editing ? "收起" : "修正 / 备注") {
                        note = session.note; end = session.end ?? model.now; editing.toggle()
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Color.grape)
                }
            }
            if !session.note.isEmpty && !editing { Text(session.note).font(.system(size: 11)).foregroundStyle(.secondary) }
            if editing {
                TextField("做到哪 / 被什么打断 / 下次如何估时", text: $note, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
                Text("忘记停？将结束时间改早一点。").font(.system(size: 10)).foregroundStyle(.secondary)
                DatePicker("实际结束", selection: $end, in: session.start...(session.end ?? model.now), displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 10))
                HStack {
                    Button("保存修正") { model.trim(session, end: end); if model.failure == nil { model.saveNote(note, session: session) }; if model.failure == nil { editing = false } }
                        .buttonStyle(.borderedProminent)
                    Button("取消") { editing = false }.buttonStyle(.plain)
                }.font(.system(size: 11))
            }
        }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calendar: CalendarBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("三个动作就够了") {
                if model.onShowDemo != nil {
                    Button("看一遍 22 秒使用演示") { model.onShowDemo?() }
                        .buttonStyle(.borderedProminent).font(.system(size: 12))
                }
                instruction("1", "拖进来，立刻开始", "把苹果日历中的一条事项拖到紫色小点或顶部入口，松手即计时，无需重新选择。")
                instruction("2", "收成小点，随手暂停", "点击圆点开始 / 暂停，拖动可挪位置；点旁边箭头展开。")
                instruction("3", "下次回来，接着做", "暂停后可留一句进度，复盘里查看和修正用时。")
            }
            settingsSection("系统右键服务") {
                Text("支持系统服务的应用，可在“服务”中选择“用 NowDo 开始计时”。是否出现在苹果日历事项的右键菜单，由苹果日历决定；没有看到时，直接拖到小点即可。")
                Text("只接收你传入的一条日程，不自动读取剪贴板。不支持将多个事项同时拖入。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            settingsSection("哪些日历显示出来") {
                if calendar.allowed && !model.demo {
                    ForEach(calendar.calendars, id: \.id) { cal in
                        Toggle(cal.title, isOn: Binding(get: { !calendar.excluded.contains(cal.id) }, set: { selected in
                            if selected { calendar.excluded.remove(cal.id) } else { calendar.excluded.insert(cal.id) }
                        })).toggleStyle(.checkbox).font(.system(size: 12))
                    }
                } else { Text(model.demo ? "结束示例后可连接自己的日历。" : "连接日历后，可选择显示的日历。") }
                Text("仅支持日历事件；苹果日历里的“提醒事项”暂未接入。日历更新会自动刷新，也可手动刷新。")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
            settingsSection("时间怎样计算") {
                Text("一次记录一件事，切换自动暂停。休眠或退出时暂停，唤醒后由你继续。意外退出会停在最后一次保存，最多可能少记约 15 秒。")
                Text("不会自动判断你在工作还是离开了电脑。忘记暂停时，在复盘中缩短这段记录。")
            }
            settingsSection("记录属于你") {
                Text("事项名称、用时和备注保存在这台 Mac。没有账号，不上传计时记录，不修改原日历；不同电脑暂不同步。")
                HStack {
                    Button("备份全部记录") { model.backup() }.disabled(model.readOnly)
                    Button("打开数据文件夹") { NSWorkspace.shared.open(AppModel.dataDirectory) }
                }.font(.system(size: 11))
                Text("日历事项改期后可能显示为新事项，已有记录仍保留。网页版 NowDo 的旧记录与此工具独立。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Text("NowDo v2.0 · 开源预览版").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { model.onQuit?() }.buttonStyle(.plain).font(.system(size: 11))
            }
        }
    }
    func instruction(_ index: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.grape).frame(width: 22, height: 22).background(Color.lavender, in: Circle())
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 12, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3) }
        }
    }
    func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.system(size: 13, weight: .semibold)); content() }
            .font(.system(size: 12)).lineSpacing(3).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PurpleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.vertical, 12)
            .frame(maxWidth: .infinity).background(Color.grape.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

func openCalendarSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") { NSWorkspace.shared.open(url) }
}
