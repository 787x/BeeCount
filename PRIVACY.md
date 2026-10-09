# Privacy Policy for BeeCount

**Last updated**: 2026-10-08

BeeCount ("we", "our", or "the app") is committed to protecting your privacy. This Privacy Policy explains how we handle your data when you use our application.

## TL;DR (Summary)

- **BeeCount itself does NOT collect your data and does NOT operate any servers**
- **We do NOT use any analytics or tracking**
- **By default your data stays on your device; nothing is sent off-device**
- **AI requests use your configured provider; voice input follows your recognition mode and may use the device system speech service**

---

## 1. Information We Collect

**We collect ZERO user data.**

BeeCount is designed with privacy-first principles:
- No user registration required (optional cloud sync only)
- No server-side data collection
- No analytics or crash reporting services
- No advertising SDKs
- No third-party tracking

## 2. How We Store Your Data

### Local Storage
- All your accounting records are stored in a local SQLite database on your device
- Data remains on your device unless you explicitly configure cloud synchronization
- We cannot access, view, or retrieve your local data

### Cloud Storage (Optional)
If you choose to enable cloud synchronization, your data is stored in:

**Option 1: Custom Supabase Instance**
- You configure your own Supabase project
- Data is stored in YOUR Supabase account
- We do NOT have access to your Supabase credentials or data
- You control the data retention and deletion

**Option 2: WebDAV Server**
- You configure your own WebDAV server (NAS, Nextcloud, etc.)
- Data is stored on YOUR server
- We do NOT have access to your WebDAV credentials or data
- You have full control over the data

**Important**: We are NOT a cloud service provider. We do not operate any servers that store your data.

## 3. Data Sharing

BeeCount itself does not collect or sell your data, and we do not operate servers that receive it.

- By default, no data leaves your device.
- If you enable **cloud sync**, data goes only to the server YOU configure (your own Supabase / WebDAV).
- If you use **AI features or voice input**, data processing follows the configured AI provider and the selected speech recognition mode, including the device system speech service when applicable (see Section 10).
- We never sell your data, and we do not use it for advertising or analytics.

## 4. Permissions We Request

The app requests the following Android permissions:

### Storage Permission (WRITE_EXTERNAL_STORAGE / READ_EXTERNAL_STORAGE)
- **Purpose**: To import/export CSV files for data backup
- **Optional**: You can still use the app without granting this permission
- **Scope**: Only accesses files you explicitly select

### Internet Permission (INTERNET)
- **Purpose**: To sync data with your own cloud service (if configured)
- **Optional**: The app works fully offline without this permission
- **Scope**: Configured cloud/AI services and, when selected, the Android system speech service.

### Microphone Permission (RECORD_AUDIO)
- **Purpose**: Voice bookkeeping and AI Chat voice input, only when requested
- **Processing**: On-device, system-service or configured cloud speech recognition as described in Section 10

### Notification Permission (POST_NOTIFICATIONS)
- **Purpose**: To show app update download notifications
- **Optional**: Not required for core functionality

### Reminder Permission (SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM)
- **Purpose**: To send accounting reminders at the time you set
- **Optional**: Only requested if you enable the reminder feature

### iOS Permissions
- **Camera**: to capture payment receipts for AI recognition (only when you use it)
- **Microphone**: for voice bookkeeping (only when you use it)
- **Photo Library**: to import/share bill data files you select

## 5. Data Security

While we don't collect your data, we implement security best practices:

- Local data is stored using SQLite with Android's built-in security
- Cloud sync uses HTTPS/TLS encryption when communicating with your servers
- Authentication credentials are stored securely using Android Keystore
- The app is open source - you can audit our code: [GitHub Repository](https://github.com/TNT-Likely/BeeCount)

## 6. Children's Privacy

The app does not knowingly collect any information from children under 13. Since we don't collect any data at all, the app can be used by anyone.

## 7. Your Rights

You have complete control over your data:

- **Access**: All your data is in plain SQLite format, you can access it anytime
- **Portability**: Export your data to CSV format
- **Deletion**: Uninstall the app or use the built-in data clearing feature
- **No Tracking**: We don't track you, so there's nothing to opt-out from

## 8. Open Source

BeeCount is fully open source under the MIT License. You can:

- Review our entire codebase: https://github.com/TNT-Likely/BeeCount
- Verify that we don't collect any data
- Build the app yourself from source
- Contribute improvements

## 9. Changes to This Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by:
- Posting the new Privacy Policy in the app
- Updating the "Last updated" date
- Publishing changes on our GitHub repository

## 10. Third-Party Services

BeeCount does NOT integrate any analytics, advertising, or crash-reporting SDKs.

The following services are involved only when you use the corresponding optional feature. Speech processing follows the selected recognition mode; the Android system service is provided by the device.

### AI features and voice input (optional)
Text and image requests go to the third-party AI provider you configure, including the text, receipt images, category names, account names and relevant transaction records needed for the request. New installations default to **Xiaomi MiMo** (`api.xiaomimimo.com`, operated by Xiaomi); existing users retain their provider choice. Other configured providers, including Zhipu GLM and custom providers, keep their existing behavior.

Speech processing depends on the recognition mode:

- **Android on-device**: raw speech is handled by the device's on-device recognition capability.
- **Android system**: audio is handled by the device's system speech recognition service. It may use a network connection; audio processing depends on that service, which may differ from BeeCount's configured AI provider.
- **Cloud AI**: raw recordings are sent to the currently configured speech provider for transcription. Other platforms continue to use cloud speech recognition.

Voice bookkeeping sends the recognized text to the configured text AI provider to extract bills. The AI Chat microphone only inserts recognized text into a draft; it is sent to the text AI provider only when the user confirms and sends the message. Cloud transcription uploads recordings before the draft exists, and system recognition may also access the network before then.

Each service processes data under its own privacy policy. AI bookkeeping and chat are off by default and require a configured text provider; local Android speech recognition does not require a cloud speech provider. The app requests consent to the current in-app notice before speech processing. Consent notice version 2 describes these paths and requires renewed consent from users who accepted version 1.

### Cloud sync (optional)
- **Supabase**: subject to [Supabase Privacy Policy](https://supabase.com/privacy)
- **WebDAV**: subject to your own server's privacy policy

## 11. Contact Us

If you have any questions about this Privacy Policy, please contact us:

- **Email**: (Add your email if you want, or remove this section)
- **GitHub Issues**: https://github.com/TNT-Likely/BeeCount/issues
- **GitHub Discussions**: https://github.com/TNT-Likely/BeeCount/discussions

## 12. Consent

By using BeeCount, you consent to this Privacy Policy.

Since we don't collect any data, there's actually nothing to consent to - your privacy is protected by default! 🔒

---

## Privacy Policy (简体中文)

**蜜蜂记账隐私政策**

**最后更新时间**: 2026-10-08

### 简要说明

- **蜜蜂记账自身不收集你的数据,也不运营任何服务器**
- **我们不使用任何分析或追踪服务**
- **默认情况下,数据只保存在你的设备,不会外发**
- **AI 请求使用配置的服务商；语音输入按识别方式处理，可能使用设备系统语音服务**

### 1. 信息收集

**我们收集零用户数据。**

蜜蜂记账采用隐私优先原则设计：
- 无需用户注册（云同步功能可选）
- 无服务器端数据收集
- 无分析或崩溃报告服务
- 无广告SDK
- 无第三方追踪

### 2. 数据存储

**本地存储**
- 所有记账记录存储在您设备上的本地SQLite数据库中
- 除非您明确配置云同步，否则数据保留在您的设备上
- 我们无法访问、查看或检索您的本地数据

**云存储（可选）**
如果您选择启用云同步，您的数据将存储在：

- **自定义Supabase实例**：存储在您自己的Supabase账户中
- **WebDAV服务器**：存储在您自己的服务器上

重要：我们不是云服务提供商，不运营任何存储您数据的服务器。

### 3. 数据共享

蜜蜂记账自身不收集、不出售你的数据,也不运营任何接收数据的服务器。

- 默认情况下,数据不会离开你的设备。
- 若你开启**云同步**,数据只发送到你自己配置的服务器(你的 Supabase / WebDAV)。
- 若你使用 **AI 功能或语音输入**，数据由配置的 AI 服务商及所选语音识别方式处理；Android 系统模式可能由设备的系统语音服务联网处理。

**AI 功能与语音输入（可选）**：文字、账单图片，以及记账或分析所需的分类名称、账户名称和相关交易记录，发送给你配置的 AI 服务商。新安装默认使用 Xiaomi MiMo（api.xiaomimimo.com，小米运营）；既有用户保留服务商选择，智谱 GLM 和自定义服务商行为不变。

语音处理取决于识别方式：

- **Android 端侧**：原始语音由设备端识别能力处理。
- **Android 系统**：使用设备的系统语音识别服务，可能联网；音频处理方式取决于该服务，不一定由 BeeCount 中配置的 AI 服务商处理。
- **云端 AI**：原始录音发送给当前配置的语音服务商转写。其它平台继续使用云端语音识别。

语音记账将识别文字发送给配置的文本 AI 服务商提取账单。AI Chat 麦克风只填写草稿，用户确认并发送消息后，文字才发送给文本 AI 服务商；云端转写在生成草稿前已上传录音，系统识别也可能在此之前联网。

各服务依各自隐私政策处理数据。AI 记账与对话默认关闭，需配置文本服务商；Android 本地语音不需要云端语音服务商。App 在语音处理前要求同意当前告知。第 2 版告知包含上述路径，已同意第 1 版的用户需重新同意。

### 4. 权限请求

应用请求以下Android权限：

- **存储权限**：用于导入/导出CSV文件（可选）
- **网络权限**：用于配置的云端/AI 服务；所选系统语音服务也可能联网
- **麦克风权限**：仅在使用语音记账或 AI Chat 语音输入时请求，按所选识别方式处理
- **通知权限**：用于显示应用更新通知（可选）
- **提醒权限**：用于发送您设置的记账提醒（可选）

### 5. 开源透明

蜜蜂记账完全开源（MIT许可）：
- 查看完整代码：https://github.com/TNT-Likely/BeeCount
- 验证我们不收集任何数据
- 从源代码自行构建
- 贡献改进

### 6. 联系我们

如有任何问题，请通过以下方式联系我们：
- GitHub Issues: https://github.com/TNT-Likely/BeeCount/issues
- GitHub Discussions: https://github.com/TNT-Likely/BeeCount/discussions

---

**Your privacy is our priority. 您的隐私是我们的首要任务。🐝**
