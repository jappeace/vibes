# OpenSLR Speech Datasets

Freely available speech datasets from https://www.openslr.org/ useful for TTS fine-tuning.

## Commonly Used for Piper TTS

### SLR 83 — Crowdsourced British/Scottish/Irish English
- URL: `https://www.openslr.org/resources/83/`
- Accents: Scottish, Irish, Welsh, various British
- Format: ZIP files per accent/gender
- CSV: `sentence_id, wav_filename, transcript` (3 columns, comma-separated)
- Scottish female: `scottish_english_female.zip` — 894 utterances
- Scottish male: `scottish_english_male.zip` — 1,649 utterances, 620MB

**Gotcha**: The CSV is comma-separated (not tab), and has 3 columns (not 2).
The wav_filename column contains the base filename without path.

### SLR 12 — LibriSpeech (American English)
- Large-scale American English audiobook data
- Good for American accent fine-tuning
- Very clean recordings

### SLR 47 — M-AILABS Speech Dataset
- Multiple languages: en, de, fr, it, es, pl, ru, uk
- High quality audiobook recordings
- LJSpeech-compatible format

## CSV Parsing Patterns

### OpenSLR 83 (3-column comma CSV)
```python
# Input: EN0234, scf_04310_01356369773, Choose the voice your assistant will use
parts = [p.strip() for p in line.split(',')]
sentence_id = parts[0]        # EN0234
wav_filename = parts[1]       # scf_04310_01356369773
transcript = ','.join(parts[2:]).strip()  # handles commas in text
```

### LJSpeech format (pipe-separated)
```python
# Input: LJ001-0001|Printing, in the only sense with which we are at present concerned
parts = line.split('|', 1)
uttid = parts[0]
text = parts[1].strip()
```

### Common CSV (2-column tab-separated)
```python
# Input: audio_001\tHello world
parts = line.split('\t', 1)
uttid = parts[0].replace('.wav', '')
text = parts[1].strip()
```

## Resampling

Piper TTS requires 22050 Hz mono audio:
```bash
sox input.wav -r 22050 -c 1 output.wav
```

sox warnings about clipping are normal and can be ignored for speech.
