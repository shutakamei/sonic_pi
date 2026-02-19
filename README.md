# sonic_pi

Sonic Pi で「MIDI のルート音追従」と「コード進行フォールバック」を切り替えながら、
ベース + ドラムのバンド伴奏を自動生成するスクリプトです。

- MIDI 入力がある間: 受け取ったノートをルートとして演奏
- MIDI 入力が途切れたら: `chord_prog` で指定したコード進行に自動復帰

対象スクリプト: `sonic_pi_band_engine.rb`

## できること

- MIDI ノートオンからルートを検出して追従
- MIDI が止まった時に自動でコード進行へフォールバック
- コード名（`Em7`, `Cmaj7`, `D/F#` など）をパースしてベースに反映
- ベースの密度・複雑さ・フィル発生率・音色を調整可能
- キック / スネア / ハイハットのドラムを同時生成

## 使い方（クイックスタート）

1. Sonic Pi を起動する
2. `sonic_pi_band_engine.rb` の中身を Sonic Pi のバッファへ貼り付ける
3. 必要に応じて設定セクションを編集する（後述）
4. Run を押して再生開始
5. MIDI キーボード（または DAW）からノートオンを送る

MIDI が届いている間は MIDI ルート優先、`midi_timeout_sec` を超えて入力がない場合は `chord_prog` に戻ります。

## 最低限ここだけ設定

以下は冒頭の「設定セクション」で調整します。

- `use_bpm 140`  
  全体テンポ
- `MIDI_PORT = "*IAC*"`  
  受信ポート名のパターン（環境に合わせて変更）
- `MIDI_CHANNEL = "*"`  
  受信チャンネル（全チャンネルなら `*`）
- `midi_timeout_sec = 4.0`  
  MIDI 無入力を判定する秒数
- `bars_per_chord = 1`  
  フォールバック時に何小節ごとで次のコードへ進むか
- `chord_prog = ["Em7", "Cmaj7", "G", "D7"]`  
  フォールバック用コード進行
- `debug = true`  
  ログ表示の ON/OFF

## よく使う調整ポイント

### ベース

`bass_cfg` で調整します。

- `density`: 発音密度
- `complexity`: 追加音の使い方（高いほど動く）
- `fill_prob`: 小節末フィルの確率
- `amp`: 音量
- `synth`: 音色（例: `:fm`）
- `distortion_mix`: 歪み量

### ドラム

`drum_cfg` で調整します。

- `density`: 全体密度
- `ghost_prob`: スネアのゴーストノート確率
- `fill_prob`: フィル傾向
- `hat_subdivision`: 8分 or 16分（`8` / `16`）
- `humanize_time`: タイミングゆらぎ

## 動作の考え方

- `midi_root_in`: MIDI ノートオン受信
- `bar_clock`: 小節進行とフォールバックコード管理
- `bass_engine`: ベースライン生成
- `drums_kick` / `drums_snare` / `drums_hat`: ドラム生成

`debug = true` の場合、Sonic Pi のログに現在モード（MIDI/FALLBACK）や選択中のコード情報が表示されます。

## トラブルシュート

- MIDI に反応しない
  - `MIDI_PORT` の文字列を環境のポート名に合わせる
  - まず `MIDI_CHANNEL = "*"` で確認する
- ずっとフォールバックになる
  - MIDI ノートオンが届いているかを `debug` ログで確認
  - `midi_timeout_sec` を長めに設定して挙動を確認
- 期待しないコード解釈になる
  - `chord_prog` の表記を `C`, `Cm`, `C7`, `Cmaj7`, `Cm7`, `CmMaj7`, `D/F#` など既知形式に寄せる

## ライセンス

必要に応じて追記してください。
