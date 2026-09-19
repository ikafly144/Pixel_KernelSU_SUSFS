# Google Pixel 10 (muzel) KernelSU-Next & SUSFS Workflow

Google Pixel 10 (`frankel`) および muzel プラットフォーム（Pixel 10 Pro / Pixel 10 Pro XL）向けに、**KernelSU-Next** および **SUSFS** を統合した **AnyKernel3.zip** を自動ビルドする GitHub Actions ワークフローです。

---

## 📱 対象端末・プラットフォーム

| 端末名 | コードネーム | プラットフォーム | 対応状況 |
| :--- | :--- | :--- | :--- |
| Google Pixel 10 | `frankel` | `muzel` | ✅ 主対象 |
| Google Pixel 10 Pro | `blazer` | `muzel` | ✅ 互換 |
| Google Pixel 10 Pro XL | `mustang` | `muzel` | ✅ 互換 |

---

## 🎯 ターゲットビルド & カーネル仕様

### 1. Linux 6.6 系 (現在のメジャー)
- **ターゲットビルド**: `CP3A.260905.009`
- **セキュリティパッチレベル**: 2026年9月5日
- **カーネルバージョン**: `6.6.127-android15-8`
- **カーネルソース**: [GrapheneOS/kernel_pixel_6.6](https://gitlab.com/grapheneos/kernel_pixel_6.6) (Tag: `2026090500`)
- **ACK サブモジュール**: [GrapheneOS/kernel_common-6.6](https://github.com/GrapheneOS/kernel_common-6.6) (`17-muzel`)

### 2. Linux 6.12 系 (将来向け・Android 17 QPR2)
- **ターゲット**: Android 17 QPR2 preview
- **カーネルソース**: [GrapheneOS/kernel_pixel_6.12](https://gitlab.com/grapheneos/kernel_pixel_6.12) (Branch: `17-qpr2-base`)

---

## ⚙️ 組み込み機能・パッチ

- **KernelSU-Next**: [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next) (`dev-susfs`)
- **SUSFS**: [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (`gki-android15-6.6` / `gki-android16-6.12`)
- **NoMount Support**: マウント分離・非表示モジュール対応
- **Baseband Guard (BBG)**: セルラー/ベースバンド保護パッチ
- **BPF Stack**: BTF + eBPF + FUSE-BPF 有効化
- **AnyKernel3 パッケージング**:
  - パッチ済みカーネル本体 (`Image`)
  - ビルドされたベンダーカーネルモジュール (`*.ko`) を同梱し、モジュール不整合（Wi-Fi/タッチ等）を防止
  - 端末判定 (`frankel`, `blazer`, `mustang`, `muzel`)

---

## 🚀 GitHub Actions によるビルド実行方法

### 1. Web UI から手動実行 (workflow_dispatch)
1. GitHub リポジトリの **Actions** タブを開きます。
2. ワークフロー **Build Pixel 10 (muzel) Kernel** を選択します。
3. **Run workflow** をクリックし、以下のパラメータを選択して実行します。
   - **Kernel Version**: `6.6 (CP3A.260905.009 / 2026-09-05)` または `6.12 (Android 17 QPR2 preview)` または `All`
   - **Release Type**: `Action` (Artifactsのみ) / `Pre-Release` / `Release`
   - **Include vendor modules**: `true`
   - **SUSFS**: `true`

### 2. GitHub CLI (`gh`) からの実行

```sh
# 6.6系カーネルのビルド (デフォルト)
gh workflow run build-pixel10.yml -f kernel_version="6.6 (CP3A.260905.009 / 2026-09-05)"

# 6.12系カーネルのビルド
gh workflow run build-pixel10.yml -f kernel_version="6.12 (Android 17 QPR2 preview)"

# 実行中のワークフローの進捗確認
gh run watch

# 最新のログを確認
gh run view --log
```

---

## 📦 インストール・適用手順

1. ワークフロー完了後、**Artifacts** または **Releases** から `AnyKernel3-Pixel10-muzel-*.zip` をダウンロードします。
2. KernelSU Manager、Magisk、TWRP、またはお好みのリカバリ環境から zip ファイルをフラッシュします。
3. 端末を再起動します。

---

## 📜 ライセンス

- カーネルソース: GPL-2.0
- 各パッチ・スクリプト: Apache-2.0 / GPL-2.0
