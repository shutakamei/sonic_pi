# Sonic Pi Band Engine
# MIDIルート追従 + コード名進行フォールバック（7th対応）

# =========================
# 設定セクション
# =========================
use_bpm 140

MIDI_PORT = "*IAC*"
MIDI_CHANNEL = "*"
midi_timeout_sec = 4.0
bars_per_chord = 1
chord_prog = ["Em7", "Cmaj7", "G", "D7"]
debug = true

bass_cfg = {
  density: 0.88,
  complexity: 0.40,
  fill_prob: 0.20,
  octave_bias: 2,
  amp: 0.85,
  synth: :fm,
  swing: 0.0,
  distortion_mix: 0.08
}

drum_cfg = {
  density: 0.9,
  ghost_prob: 0.18,
  fill_prob: 0.2,
  hat_subdivision: 8,  # 8 or 16
  humanize_time: 0.01
}

# =========================
# ユーティリティ
# =========================
def root_token_to_symbol(tok)
  map = {
    "C" => :c, "C#" => :cs, "Db" => :db,
    "D" => :d, "D#" => :ds, "Eb" => :eb,
    "E" => :e,
    "F" => :f, "F#" => :fs, "Gb" => :gb,
    "G" => :g, "G#" => :gs, "Ab" => :ab,
    "A" => :a, "A#" => :as, "Bb" => :bb,
    "B" => :b
  }
  map[tok]
end

def root_token_to_pc(tok)
  map = {
    "C" => 0, "C#" => 1, "Db" => 1,
    "D" => 2, "D#" => 3, "Eb" => 3,
    "E" => 4,
    "F" => 5, "F#" => 6, "Gb" => 6,
    "G" => 7, "G#" => 8, "Ab" => 8,
    "A" => 9, "A#" => 10, "Bb" => 10,
    "B" => 11
  }
  map[tok]
end

def quality_to_offsets(tag)
  {
    maj: [0, 4, 7],
    min: [0, 3, 7],
    dom7: [0, 4, 7, 10],
    maj7: [0, 4, 7, 11],
    min7: [0, 3, 7, 10],
    minmaj7: [0, 3, 7, 11]
  }[tag]
end

def parse_chord_name(name)
  # 例: C, Cm, C7, Cmaj7, CM7, Cm7, CmM7, CmMaj7, Bbmaj7, F#7, D/F#
  m = /^([A-G])([#b]?)([^\/]*)?(?:\/([A-G][#b]?))?$/.match(name.to_s.strip)
  return nil unless m

  root_tok = "#{m[1]}#{m[2]}"
  suffix = (m[3] || "").strip
  bass_tok = m[4]

  quality = case suffix
            when "", "M", "maj"
              :maj
            when "m", "min"
              :min
            when "7"
              :dom7
            when "maj7", "M7"
              :maj7
            when "m7", "min7"
              :min7
            when "mM7", "mMaj7", "minmaj7"
              :minmaj7
            else
              # 既知外は安全にメジャー扱い
              :maj
            end

  root_pc = root_token_to_pc(root_tok)
  root_sym = root_token_to_symbol(root_tok)
  return nil if root_pc.nil? || root_sym.nil?

  bass_note_opt = nil
  if bass_tok
    bass_pc = root_token_to_pc(bass_tok)
    bass_note_opt = 36 + bass_pc if bass_pc
  end

  {
    root_sym: root_sym,
    root_pc: root_pc,
    quality_tag: quality,
    offsets: quality_to_offsets(quality),
    bass_note_opt: bass_note_opt
  }
end

def normalize_to_range(n, low, high)
  x = n
  x += 12 while x < low
  x -= 12 while x > high
  x
end

def choose_step_with_leap_control(candidates, prev_note)
  return candidates.choose if prev_note.nil?

  near = candidates.select { |n| (n - prev_note).abs <= 7 }
  octave = candidates.select { |n| (n - prev_note).abs <= 12 }

  if one_in(100) && !octave.empty?
    octave.choose
  elsif !near.empty?
    near.choose
  elsif !octave.empty?
    octave.choose
  else
    candidates.choose
  end
end

def build_fallback_harmony(chord_name, low: 36)
  parsed = parse_chord_name(chord_name)
  return nil if parsed.nil?

  root = low + parsed[:root_pc]
  tones = parsed[:offsets].map { |o| root + o }
  {
    root: root,
    chord_tones: tones,
    parsed: parsed
  }
end

def build_midi_harmony(root_midi)
  root = normalize_to_range(root_midi, 28, 52) # E1-E3 相当の低域
  major_penta = [0, 2, 4, 7, 9]
  minor_penta = [0, 3, 5, 7, 10]
  scale = one_in(2) ? major_penta : minor_penta

  tones = scale.map { |o| root + o }
  {
    root: root,
    chord_tones: tones,
    parsed: {
      root_sym: nil,
      quality_tag: :midi_root,
      offsets: scale,
      bass_note_opt: nil
    }
  }
end

# =========================
# 状態初期化
# =========================
set :root_midi, nil
set :last_midi_time, -999.0
set :bar_index, 0
set :section, :A
set :fallback_chord_name, chord_prog[0]
set :parsed_debug, nil
set :bass_prev_note, nil

# =========================
# ループ構成
# =========================
live_loop :midi_root_in do
  use_real_time
  n, vel = sync "/midi:#{MIDI_PORT}:#{MIDI_CHANNEL}:note_on"
  next if vel <= 0

  set :root_midi, n
  set :last_midi_time, vt

  if debug
    puts "[MIDI] root=#{n} vel=#{vel} time=#{vt.round(3)}"
  end
end

live_loop :bar_clock do
  bar_i = get(:bar_index) || 0
  last = get(:last_midi_time) || -999.0
  use_midi = (vt - last) <= midi_timeout_sec

  unless use_midi
    if (bar_i % bars_per_chord) == 0
      idx = (bar_i / bars_per_chord) % chord_prog.length
      chord_name = chord_prog[idx]
      set :fallback_chord_name, chord_name

      parsed = parse_chord_name(chord_name)
      set :parsed_debug, parsed

      if debug
        if parsed
          puts "[BAR] fallback chord=#{chord_name} quality=#{parsed[:quality_tag]} offsets=#{parsed[:offsets].inspect}"
        else
          puts "[BAR] fallback chord parse failed: #{chord_name}"
        end
      end
    end
  end

  set :bar_index, bar_i + 1
  set :section, ((bar_i / 8).even? ? :A : :B)
  sleep 4
end

live_loop :bass_engine do
  last = get(:last_midi_time) || -999.0
  use_midi = (vt - last) <= midi_timeout_sec
  bar_i = get(:bar_index) || 0

  harmony = if use_midi && !get(:root_midi).nil?
              build_midi_harmony(get(:root_midi))
            else
              build_fallback_harmony(get(:fallback_chord_name) || chord_prog[0], low: 36)
            end
  harmony ||= build_fallback_harmony(chord_prog[0], low: 36)

  root = harmony[:parsed][:bass_note_opt] || harmony[:root]
  chord_tones = harmony[:chord_tones]

  pool = chord_tones.clone
  if bass_cfg[:complexity] > 0.2
    ext = [root + 2, root + 5, root + 9].map { |n| normalize_to_range(n, 28, 55) }
    pool += ext
  end
  pool = pool.map { |n| normalize_to_range(n, 28, 55) }.uniq

  patterns = [
    [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
    [0.5, 0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5],
    [0.5, 0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5]
  ]

  pat = patterns.choose
  pos = 0.0
  prev_note = get(:bass_prev_note)

  with_fx :distortion, mix: bass_cfg[:distortion_mix] do
    use_synth bass_cfg[:synth]
    pat.each_with_index do |dur, i|
      is_down = (pos % 1.0).zero?
      is_bar_start = pos.zero?

      if rand < bass_cfg[:density]
        note = if is_bar_start || (is_down && rand < 0.72)
                 root
               else
                 choose_step_with_leap_control(pool, prev_note)
               end

        cutoff = rrand(75, 100)
        play note, release: [0.12, dur * 0.9].max, amp: bass_cfg[:amp], cutoff: cutoff
        prev_note = note
      end

      if i >= pat.length - 2 && rand < bass_cfg[:fill_prob]
        # 小節末フィル（16分）
        2.times do
          f = choose_step_with_leap_control(pool, prev_note)
          play f, release: 0.08, amp: bass_cfg[:amp] * 0.85, cutoff: rrand(80, 105)
          prev_note = f
          sleep 0.25
          pos += 0.25
        end
      else
        sleep dur
        pos += dur
      end
    end
  end

  set :bass_prev_note, prev_note

  if debug
    mode = use_midi ? "MIDI" : "FALLBACK"
    q = harmony[:parsed][:quality_tag]
    puts "[BASS] mode=#{mode} root=#{root} quality=#{q} tones=#{chord_tones.inspect} bar=#{bar_i}"
  end
end

live_loop :drums_kick do
  bar_i = get(:bar_index) || 0
  16.times do |step|
    p = 0.0
    p += 0.92 if step == 0
    p += 0.35 if step == 8
    p += 0.16 if [3, 6, 10, 14].include?(step)
    p += 0.12 if rand < drum_cfg[:fill_prob] && step >= 12

    if rand < (p * drum_cfg[:density])
      sleep rrand(0, drum_cfg[:humanize_time])
      sample :bd_haus, amp: 1.7
    end
    sleep 0.25
  end
end

live_loop :drums_snare do
  16.times do |step|
    main = [4, 12].include?(step)
    ghost = [2, 6, 10, 14].include?(step) && rand < drum_cfg[:ghost_prob]

    if main
      sleep rrand(0, drum_cfg[:humanize_time])
      sample :sn_dolf, amp: 1.25
    elsif ghost
      sleep rrand(0, drum_cfg[:humanize_time])
      sample :sn_dolf, amp: 0.45
    end
    sleep 0.25
  end
end

live_loop :drums_hat do
  sub = drum_cfg[:hat_subdivision] == 16 ? 0.25 : 0.5
  steps = (4.0 / sub).to_i

  steps.times do |i|
    if rand < 0.88
      sleep rrand(0, drum_cfg[:humanize_time])
      sample :drum_cymbal_closed, amp: 0.7, finish: 0.12
    end

    if i >= (steps - 2) && rand < 0.08
      sample :drum_cymbal_open, amp: 0.45, sustain: 0.05, release: 0.12
    end

    sleep sub
  end
end
